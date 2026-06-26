import os
import glob
import shutil
import zipfile
import readline
from pathlib import Path


def setup_path_completion():
    """
    让 input() 支持类似 bash 的路径 Tab 补全。
    支持当前目录、相对路径、绝对路径。
    """
    def complete(text, state):
        # 处理 ~
        expanded_text = os.path.expanduser(text)

        # 如果输入为空，列出当前目录
        if not expanded_text:
            matches = glob.glob("*")
        else:
            matches = glob.glob(expanded_text + "*")

        results = []
        for m in matches:
            # 目录后面加 /
            if os.path.isdir(m):
                m += "/"

            # 如果用户输入的是 ~ 开头，尽量显示回 ~ 形式
            if text.startswith("~"):
                home = os.path.expanduser("~")
                if m.startswith(home):
                    m = "~" + m[len(home):]

            results.append(m)

        # readline 需要返回第 state 个候选
        try:
            return results[state]
        except IndexError:
            return None

    readline.set_completer_delims(" \t\n")
    readline.parse_and_bind("tab: complete")
    readline.set_completer(complete)


def decode_zip_name(name: str) -> str:
    """
    修复 Windows 中文环境打包 ZIP 后，在 Linux 解压文件名乱码的问题。
    ZIP 内部若没有 UTF-8 标志，Python 默认可能按 cp437 解码；
    这里先把 cp437 还原为原始字节，再按 GBK/CP936/GB18030 尝试解码。
    """
    try:
        raw = name.encode("cp437")
    except UnicodeEncodeError:
        return name

    for enc in ("gbk", "cp936", "gb18030", "utf-8"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue

    return name


def safe_target_path(out_dir: Path, fixed_name: str) -> Path | None:
    """
    防止 zip slip：
    避免压缩包里出现 /absolute/path 或 ../../evil 这种路径。
    """
    fixed_name = fixed_name.replace("\\", "/").lstrip("/")
    parts = [p for p in fixed_name.split("/") if p not in ("", ".", "..")]

    if not parts:
        return None

    return out_dir.joinpath(*parts)


def extract_zip_with_fixed_names(zip_path: Path, out_dir: Path, overwrite: bool = True):
    if not zip_path.exists():
        raise FileNotFoundError(f"文件不存在：{zip_path}")

    if not zip_path.is_file():
        raise ValueError(f"不是文件：{zip_path}")

    if zip_path.suffix.lower() != ".zip":
        print(f"警告：文件后缀不是 .zip：{zip_path}")

    if out_dir.exists():
        if overwrite:
            print(f"输出目录已存在，将删除后重新解压：{out_dir}")
            shutil.rmtree(out_dir)
        else:
            raise FileExistsError(f"输出目录已存在：{out_dir}")

    out_dir.mkdir(parents=True, exist_ok=True)

    count = 0

    with zipfile.ZipFile(zip_path, "r") as zf:
        for info in zf.infolist():
            fixed_name = decode_zip_name(info.filename)
            target = safe_target_path(out_dir, fixed_name)

            if target is None:
                continue

            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info, "r") as src, open(target, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                count += 1

    print(f"解压完成：{out_dir}")
    print(f"文件数量：{count}")


def main():
    setup_path_completion()

    print("请输入要解压的 zip 文件路径，支持 Tab 补全。")
    zip_input = input("zip 文件：").strip()

    if not zip_input:
        print("未输入文件名，退出。")
        return

    zip_path = Path(os.path.expanduser(zip_input)).resolve()

    default_out = zip_path.with_suffix("").name

    print()
    print(f"默认输出目录：{default_out}")
    out_input = input("输出目录，直接回车使用默认：").strip()

    if out_input:
        out_dir = Path(os.path.expanduser(out_input)).resolve()
    else:
        out_dir = Path(default_out).resolve()

    extract_zip_with_fixed_names(zip_path, out_dir, overwrite=True)


if __name__ == "__main__":
    main()