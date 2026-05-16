/**
 * 项目路径解析：CLI 与 Runtime 的 working_dir 对齐。
 * Runtime 约定：manifest 位于 `{working_dir}/.metrica/project.json`。
 */

/** 去除 CLI 引号 */
export function stripCliQuotes(s: string): string {
  const t = s.trim();
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.slice(1, -1);
  }
  return t;
}

/** 将 Runtime 返回的 manifest 绝对路径还原为项目根（working_dir） */
export function projectRootFromManifestPath(manifestPath: string): string {
  const norm = manifestPath.replace(/\\/g, '/');
  const marker = '/.metrica/project.json';
  if (norm.endsWith(marker)) {
    return norm.slice(0, -marker.length) || '/';
  }
  const idx = norm.lastIndexOf('/.metrica/');
  if (idx >= 0) return norm.slice(0, idx) || '/';
  const slash = norm.lastIndexOf('/');
  return slash > 0 ? norm.slice(0, slash) : '.';
}

/**
 * save / load CLI：用户给定路径 → `project_context.working_dir`
 * - 以 `.metrica` 或 `.json` 结尾：取父目录（用于书签式路径或 manifest 文件）
 * - 含 `/.metrica/project.json`：取 `.metrica` 的父目录
 * - 否则视为项目根目录本身
 */
export function resolveProjectWorkingDirFromUserPath(userPath: string): string {
  let p = stripCliQuotes(userPath).replace(/\\/g, '/');
  p = p.replace(/\/+$/, '');
  if (!p) return '.';
  if (p.includes('/.metrica/project.json')) {
    const idx = p.indexOf('/.metrica/');
    return idx >= 0 ? p.slice(0, idx) || '/' : p;
  }
  const lower = p.toLowerCase();
  if (lower.endsWith('.metrica') || lower.endsWith('.json')) {
    const slash = p.lastIndexOf('/');
    return slash > 0 ? p.slice(0, slash) : '.';
  }
  return p;
}
