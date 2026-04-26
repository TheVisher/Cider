const esbuild = require('esbuild');
const fs = require('fs');
const path = require('path');

const distDir = path.join(__dirname, 'dist');
const resourceDir = path.join(__dirname, '..', 'Sources', 'Cider', 'Resources', 'TipTapEditor');

async function build() {
  // Build JS bundle
  await esbuild.build({
    entryPoints: [path.join(__dirname, 'src', 'editor.js')],
    bundle: true,
    outfile: path.join(distDir, 'editor.js'),
    format: 'iife',
    target: ['safari17'],
    minify: true,
    sourcemap: false,
  });

  // Build CSS bundle
  await esbuild.build({
    entryPoints: [path.join(__dirname, 'src', 'editor.css')],
    bundle: true,
    outfile: path.join(distDir, 'editor.css'),
    minify: true,
  });

  // Generate editor.html
  const html = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<link rel="stylesheet" href="editor.css">
</head>
<body>
<div id="editor"></div>
<script src="editor.js"></script>
</body>
</html>`;

  fs.writeFileSync(path.join(distDir, 'editor.html'), html);

  // Copy dist to Resources
  fs.rmSync(resourceDir, { recursive: true, force: true });
  fs.mkdirSync(resourceDir, { recursive: true });
  for (const file of fs.readdirSync(distDir)) {
    fs.copyFileSync(path.join(distDir, file), path.join(resourceDir, file));
  }

  console.log('Build complete. Files copied to Resources/TipTapEditor/');
}

build().catch((err) => {
  console.error(err);
  process.exit(1);
});
