#!/usr/bin/env python3
"""只读检查暂存区或尚未交付的提交；仅依赖 Python 3 和 Git。"""

import argparse
import os
from pathlib import Path
import subprocess
import sys


BLOCKED_DIRS = {
    ".godot", ".import", ".mono", ".vscode", ".idea", ".codex", ".agents",
    ".cursor", ".claude", ".vs", ".cache", "__pycache__", "build", "builds",
    "dist", "exports", "bin", "obj", "assets", "art", "audio", "textures",
    "models", "fonts", "raw_assets", "large_files", "素材", "原始素材", "大文件",
}
BLOCKED_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tga", ".tif",
    ".tiff", ".svg", ".ico", ".psd", ".psb", ".kra", ".ase", ".aseprite",
    ".hdr", ".exr", ".dds", ".ktx", ".ktx2", ".wav", ".ogg", ".mp3",
    ".flac", ".m4a", ".aac", ".mid", ".mp4", ".mov", ".webm", ".avi",
    ".mkv", ".blend", ".blend1", ".fbx", ".glb", ".gltf", ".obj", ".mtl",
    ".dae", ".usd", ".usda", ".usdc", ".usdz", ".abc", ".ttf", ".otf",
    ".woff", ".woff2", ".import", ".res", ".scn", ".pck", ".exe", ".dll",
    ".so", ".dylib", ".apk", ".aab", ".zip", ".rar", ".7z", ".tar",
    ".gz", ".bz2", ".xz", ".pem", ".key", ".pfx", ".p12", ".translation",
    ".code-workspace", ".suo", ".user", ".log", ".tmp", ".temp", ".bak", ".swp",
}
BLOCKED_NAMES = {"export.cfg", "export_credentials.cfg", ".ds_store", "thumbs.db", "desktop.ini"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".", help="实际仓库目录，默认当前目录")
    parser.add_argument("--scope", choices=("staged", "outgoing"), required=True)
    parser.add_argument("--base", default="origin/main", help="outgoing 的远端基线；先 fetch")
    parser.add_argument("--limit-mib", type=int, default=10)
    args = parser.parse_args()
    if args.limit_mib <= 0:
        parser.error("--limit-mib 必须大于 0")
    root = Path(args.repo).resolve()

    def git(*command, data=None, allowed=(0,)):
        result = subprocess.run(
            ["git", "-C", str(root), *command], input=data,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if result.returncode not in allowed:
            raise RuntimeError(result.stderr.decode("utf-8", "replace").strip() or str(command))
        return result.stdout

    git("rev-parse", "--show-toplevel")
    # read-only commands and --no-optional-locks environment avoid index refresh writes.
    entries = []
    if args.scope == "staged":
        paths = set(filter(None, git("diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").split(b"\0")))
        for row in filter(None, git("ls-files", "--stage", "-z").split(b"\0")):
            header, path = row.split(b"\t", 1)
            mode, oid, stage = header.split()
            if stage != b"0":
                raise RuntimeError("存在未解决的索引冲突，请先处理")
            if path in paths:
                if mode == b"160000":
                    raise RuntimeError("新增/修改了子模块，需要另行核对内容与来源")
                entries.append(("index", path, oid))
    else:
        base = git("rev-parse", "--verify", args.base + "^{commit}").strip().decode("ascii")
        if subprocess.run(
            ["git", "-C", str(root), "merge-base", "--is-ancestor", base, "HEAD"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ).returncode != 0:
            raise RuntimeError("HEAD 尚未基于所选主线；请先 fetch/rebase，再执行 outgoing 检查")
        commits = git("rev-list", "--reverse", base + "..HEAD").splitlines()
        for raw_commit in commits:
            commit = raw_commit.decode("ascii")
            changed = set(filter(None, git(
                "diff-tree", "--root", "--no-commit-id", "-r", "-m", "--name-only",
                "--diff-filter=ACMR", "-z", commit,
            ).split(b"\0")))
            for row in filter(None, git("ls-tree", "-r", "-z", "--full-tree", commit).split(b"\0")):
                header, path = row.split(b"\t", 1)
                mode, kind, oid = header.split()
                if path in changed:
                    if kind != b"blob":
                        raise RuntimeError("待交付历史包含子模块变更，需要另行核对")
                    entries.append((commit[:12], path, oid))

    paths = sorted({path for _, path, _ in entries})
    ignored = set()
    if paths:
        ignored = set(filter(None, git(
            "check-ignore", "--no-index", "--stdin", "-z",
            data=b"\0".join(paths) + b"\0", allowed=(0, 1),
        ).split(b"\0")))
    ids = sorted({oid for _, _, oid in entries})
    sizes = {}
    if ids:
        for row in git("cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)", data=b"\n".join(ids) + b"\n").splitlines():
            oid, kind, size = row.split()
            if kind != b"blob":
                raise RuntimeError("待检查对象不是文件 blob")
            sizes[oid] = int(size)

    findings = []
    seen = set()
    for version, raw_path, oid in entries:
        path = raw_path.decode("utf-8", "replace")
        lower = path.lower()
        parts = lower.split("/")
        name = parts[-1]
        reasons = []
        if raw_path in ignored:
            reasons.append("命中仓库忽略规则（包含已跟踪文件）")
        blocked_parts = {part for part in parts[:-1] if part in BLOCKED_DIRS}
        if parts[:2] == [".agents", "skills"]:
            blocked_parts.discard(".agents")
        if blocked_parts:
            reasons.append("工具/缓存/素材等排除目录")
        if Path(name).suffix in BLOCKED_SUFFIXES or name in BLOCKED_NAMES or name.endswith("~"):
            reasons.append("素材、产物、凭据或临时文件后缀/名称")
        if name == ".env" or (name.startswith(".env.") and name not in {".env.example", ".env.template"}):
            reasons.append("本机环境配置")
        if sizes[oid] >= args.limit_mib * 1024 * 1024:
            reasons.append(f"文件达到 {args.limit_mib} MiB（{sizes[oid]} 字节）")
        # A single unsafe blob/path need only be reported once even if multiple commits touch it.
        key = (raw_path, oid)
        if reasons and key not in seen:
            findings.append((version, path, reasons))
            seen.add(key)
    for version, path, reasons in findings:
        print(f"阻止交付 [{version}] {path!r}: {'；'.join(reasons)}")
    if findings:
        print(f"FAIL: {len(findings)} 个文件版本需要处理；没有修改仓库或执行推送。")
        return 1
    print(f"PASS: {args.scope} 检查 {len(entries)} 个路径版本；未发现已知排除项或超限文件。")
    print("仅检查路径策略与大小，不代替差异审核、未知素材识别、秘密内容扫描或 Godot 验收。")
    return 0


if __name__ == "__main__":
    os.environ["GIT_OPTIONAL_LOCKS"] = "0"
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"检查未完成: {error}", file=sys.stderr)
        sys.exit(2)
