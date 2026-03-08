const esbuild = require('esbuild');
const fs = require('fs');
const path = require('path');

const distDir = path.join(__dirname, 'dist');
const resourceDir = path.join(__dirname, '..', 'Sources', 'Cider', 'Resources', 'ExcalidrawEditor');

async function build() {
  // Build JS bundle (React + Excalidraw)
  await esbuild.build({
    entryPoints: [path.join(__dirname, 'src', 'index.jsx')],
    bundle: true,
    outfile: path.join(distDir, 'excalidraw.js'),
    format: 'iife',
    target: ['safari17'],
    minify: true,
    sourcemap: false,
    jsx: 'automatic',
    jsxImportSource: 'react',
    loader: {
      '.woff2': 'dataurl',
      '.woff': 'dataurl',
      '.ttf': 'dataurl',
      '.png': 'dataurl',
      '.svg': 'dataurl',
    },
    conditions: ['production'],
    define: {
      'process.env.NODE_ENV': '"production"',
    },
  });

  // Build CSS bundle
  await esbuild.build({
    entryPoints: [path.join(__dirname, 'src', 'styles.css')],
    bundle: true,
    outfile: path.join(distDir, 'excalidraw.css'),
    minify: true,
    alias: {
      'excalidraw-css': path.join(__dirname, 'node_modules', '@excalidraw', 'excalidraw', 'dist', 'prod', 'index.css'),
    },
    loader: {
      '.woff2': 'dataurl',
      '.woff': 'dataurl',
      '.ttf': 'dataurl',
      '.png': 'dataurl',
      '.svg': 'dataurl',
    },
  });

  // Generate index.html
  const html = `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<link rel="stylesheet" href="excalidraw.css">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body, #root { width: 100%; height: 100%; overflow: hidden; background: transparent; }
</style>
</head>
<body>
<div id="root"></div>
<script src="excalidraw.js"></script>
</body>
</html>`;

  fs.mkdirSync(distDir, { recursive: true });
  fs.writeFileSync(path.join(distDir, 'index.html'), html);

  // Copy dist to Resources
  fs.mkdirSync(resourceDir, { recursive: true });
  for (const file of fs.readdirSync(distDir)) {
    fs.copyFileSync(path.join(distDir, file), path.join(resourceDir, file));
  }

  console.log('Build complete. Files copied to Resources/ExcalidrawEditor/');
}

build().catch((err) => {
  console.error(err);
  process.exit(1);
});
