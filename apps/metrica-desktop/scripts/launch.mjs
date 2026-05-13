#!/usr/bin/env node
import { spawn, execSync } from 'child_process';
import { existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, '../../..');
const desktopBin = resolve(__dirname, '../src-tauri/target/release/metrica-desktop');
const runtimeBin = resolve(repoRoot, 'runtime/metrica-runtime/target/release/metrica-runtime');
const lockFile = '/tmp/metrica-desktop.lock';

// 查找 Julia 二进制
function findJuliaBin() {
  // 环境变量优先
  if (process.env.JULIA_BIN && existsSync(process.env.JULIA_BIN)) {
    return process.env.JULIA_BIN;
  }

  // 查找 juliaup 安装
  const juliaDir = `${process.env.HOME}/.julia/juliaup`;
  try {
    const dirs = execSync(`ls -d "${juliaDir}"/julia-* 2>/dev/null`, { shell: true })
      .toString().trim().split('\n').filter(Boolean);
    for (const dir of dirs) {
      const bin = `${dir}/Julia-*.app/Contents/Resources/julia/bin/julia`;
      const expanded = execSync(`ls ${bin} 2>/dev/null`, { shell: true })
        .toString().trim();
      if (expanded && existsSync(expanded)) {
        return expanded;
      }
    }
  } catch {}

  // 回退到 PATH 上的 julia
  return 'julia';
}

// 清理残留
try { execSync(`pkill -9 -f metrica-desktop 2>/dev/null`, { stdio: 'ignore' }); } catch {}
try { execSync(`pkill -9 -f metrica-runtime 2>/dev/null`, { stdio: 'ignore' }); } catch {}
try { execSync(`rm -f "${lockFile}"`, { stdio: 'ignore' }); } catch {}

const juliaBin = findJuliaBin();
console.log(`Julia: ${juliaBin}`);
console.log(`Runtime: ${runtimeBin}`);
console.log(`Desktop: ${desktopBin}`);

process.env.JULIA_BIN = juliaBin;
process.env.METRICA_RUNTIME_BIN = runtimeBin;

const child = spawn(desktopBin, [], {
  stdio: 'inherit',
  env: process.env,
  detached: true,
});

child.on('error', (err) => {
  console.error('启动失败:', err.message);
  process.exit(1);
});

child.on('exit', (code) => {
  if (code !== 0) {
    console.error(`桌面应用退出，代码: ${code}`);
  }
});

child.unref();
console.log('Metrica 桌面应用已启动。');
