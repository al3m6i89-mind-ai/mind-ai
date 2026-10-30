"""Upload validation: the extension must be allowed AND the bytes must match it."""
import io
import zipfile

OLE_MAGIC = b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"

# ext -> (kind, mime, label)
SUPPORTED = {
    "pdf": ("file", "application/pdf", "PDF"),
    "docx": ("file", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "Word"),
    "doc": ("file", "application/msword", "Word"),
    "pptx": ("file", "application/vnd.openxmlformats-officedocument.presentationml.presentation", "PowerPoint"),
    "ppt": ("file", "application/vnd.ms-powerpoint", "PowerPoint"),
    "xlsx": ("file", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "Excel"),
    "xls": ("file", "application/vnd.ms-excel", "Excel"),
    "txt": ("file", "text/plain; charset=utf-8", "TXT"),
    "csv": ("file", "text/csv; charset=utf-8", "CSV"),
    "md": ("file", "text/markdown; charset=utf-8", "Markdown"),
    "markdown": ("file", "text/markdown; charset=utf-8", "Markdown"),
    "jpg": ("image", "image/jpeg", "JPG"),
    "jpeg": ("image", "image/jpeg", "JPEG"),
    "png": ("image", "image/png", "PNG"),
    "webp": ("image", "image/webp", "WEBP"),
}

OOXML_DIR = {"docx": "word/", "pptx": "ppt/", "xlsx": "xl/"}


class UploadRejected(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def extension_of(filename: str) -> str:
    return filename.rsplit(".", 1)[-1].lower() if "." in filename else ""


def _looks_like_text(data: bytes) -> bool:
    sample = data[:65536]
    if b"\x00" in sample and not sample.startswith((b"\xff\xfe", b"\xfe\xff")):
        return False
    for enc in ("utf-8-sig", "utf-16", "cp1256"):
        try:
            sample.decode(enc)
            return True
        except UnicodeDecodeError:
            continue
    return False


def validate(filename: str, data: bytes) -> tuple[str, str, str]:
    """Return (ext, kind, mime) or raise UploadRejected."""
    ext = extension_of(filename)
    if ext not in SUPPORTED:
        raise UploadRejected("unsupported_type", f"File type '.{ext or '?'}' is not supported.")
    if not data:
        raise UploadRejected("empty_file", "The file is empty.")
    kind, mime, _ = SUPPORTED[ext]

    ok = True
    if ext == "pdf":
        ok = data[:1024].lstrip().startswith(b"%PDF")
    elif ext in OOXML_DIR:
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as zf:
                names = zf.namelist()
            ok = "[Content_Types].xml" in names and any(n.startswith(OOXML_DIR[ext]) for n in names)
        except zipfile.BadZipFile:
            ok = False
    elif ext in ("doc", "ppt", "xls"):
        ok = data.startswith(OLE_MAGIC)
    elif ext in ("txt", "csv", "md", "markdown"):
        ok = _looks_like_text(data)
    elif ext in ("jpg", "jpeg"):
        ok = data.startswith(b"\xff\xd8\xff")
    elif ext == "png":
        ok = data.startswith(b"\x89PNG\r\n\x1a\n")
    elif ext == "webp":
        ok = data[:4] == b"RIFF" and data[8:12] == b"WEBP"

    if not ok:
        raise UploadRejected("content_mismatch", f"The file content does not match a real .{ext} file.")
    return ext, kind, mime
