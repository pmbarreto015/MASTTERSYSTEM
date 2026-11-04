"""Atualiza Dart/assets usando uma base nativa conferida, antes de alinhar e assinar."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def digest(stream):
    result = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    base, output = args.base.resolve(), args.output.resolve()
    if not output.is_relative_to(ROOT / "build") or base == output:
        raise RuntimeError("Destino deve ser um arquivo distinto dentro de build.")
    native_inputs = list((ROOT / "android/app/src/main").rglob("*")) + [
        ROOT / "android/app/build.gradle.kts", ROOT / "android/settings.gradle.kts",
        ROOT / "pubspec.lock",
    ]
    newer = [str(p.relative_to(ROOT)) for p in native_inputs
             if p.is_file() and p.stat().st_mtime > base.stat().st_mtime]
    if newer:
        raise RuntimeError(f"Fontes nativas posteriores a base: {newer}")
    assets = ROOT / "build/app/intermediates/flutter/release/flutter_assets"
    aot = ROOT / "build/app/intermediates/flutter/release"
    abis = ("armeabi-v7a", "arm64-v8a", "x86_64")
    replacements = {f"lib/{abi}/libapp.so": aot / abi / "app.so" for abi in abis}
    replacements.update({"assets/flutter_assets/" + p.relative_to(assets).as_posix(): p
                         for p in assets.rglob("*") if p.is_file()})
    if any(p.suffix.lower() in (".apk", ".zip", ".exe") for p in assets.rglob("*")):
        raise RuntimeError("Instaladores nao podem ser embutidos no cliente.")
    for path in replacements.values():
        if not path.is_file():
            raise RuntimeError(f"Arquivo compilado ausente: {path}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(base) as original:
        native_count = 0
        for info in original.infolist():
            if info.filename.startswith("lib/") and info.filename.endswith(".so") and info.filename not in replacements:
                current = ROOT / "build/app/intermediates/stripped_native_libs/release/stripReleaseDebugSymbols/out" / info.filename
                with original.open(info) as old, current.open("rb") as new:
                    if digest(old) != digest(new):
                        raise RuntimeError(f"Biblioteca nativa diferente: {info.filename}")
                native_count += 1
        with original.open("assets/flutter_assets/NOTICES.Z") as old, (assets / "NOTICES.Z").open("rb") as new:
            if digest(old) != digest(new):
                raise RuntimeError("As dependencias nao correspondem a base.")
        with zipfile.ZipFile(output, "w", allowZip64=True) as updated:
            for info in original.infolist():
                signature = info.filename.upper().startswith("META-INF/") and info.filename.upper().endswith((".SF", ".RSA", ".DSA", ".EC", "MANIFEST.MF"))
                if signature or info.filename.startswith("assets/flutter_assets/") or info.filename in replacements:
                    continue
                with original.open(info) as source, updated.open(info, "w") as target:
                    shutil.copyfileobj(source, target, 1024 * 1024)
            for name, path in sorted(replacements.items()):
                updated.write(path, name, compress_type=zipfile.ZIP_STORED if name.startswith("lib/") else zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(output) as result:
        for name, path in replacements.items():
            with result.open(name) as actual, path.open("rb") as expected:
                if digest(actual) != digest(expected):
                    raise RuntimeError(f"Payload divergente: {name}")
    with base.open("rb") as source:
        base_hash = digest(source)
    report = {"base": str(base), "base_sha256": base_hash,
              "native_libraries_verified": native_count,
              "replaced_files": list(replacements), "unsigned_apk": str(output)}
    (output.parent / "reempacotamento-android.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    print(f"Base nativa conferida ({native_count} bibliotecas); tres AOT e assets atualizados.", flush=True)


if __name__ == "__main__":
    main()
