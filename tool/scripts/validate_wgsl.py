#!/usr/bin/env python3
import sys
import tempfile
import re
import subprocess
import os


def main():
    if len(sys.argv) < 2:
        print("Usage: validate_wgsl.py PATH")
        return 2

    src = sys.argv[1]
    fd, dst = tempfile.mkstemp(suffix='.wgsl')
    os.close(fd)
    try:
        with open(src, 'r', encoding='utf8') as f:
            text = f.read()

        # Strip host directives and placeholders
        text = re.sub(r'(?m)^\s*#import.*\r?\n', '', text)
        text = re.sub(r'#\{[^}]*\}', '0', text)

        # Ensure minimal VertexOutput struct exists for standalone validation
        if not re.search(r'\bstruct\s+VertexOutput\b', text):
            vo_def = '\nstruct VertexOutput { @location(0) uv: vec2<f32>, };\n\n'
            text = vo_def + text

        with open(dst, 'w', encoding='utf8') as f:
            f.write(text)

        print('Validating preprocessed shader:', dst)
        subprocess.run(['naga', dst, '--input-kind', 'wgsl'])
    finally:
        try:
            os.remove(dst)
        except Exception:
            pass


if __name__ == '__main__':
    sys.exit(main())
