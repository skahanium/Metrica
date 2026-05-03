import { create } from 'zustand';
import type { ProjectManifest, RunRecord, DataOp } from '../types/protocol';

const RECENT_PROJECTS_KEY = 'metrica.recentProjects';

function loadRecentProjects(): string[] {
  try {
    const raw = globalThis.localStorage?.getItem(RECENT_PROJECTS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((v): v is string => typeof v === 'string') : [];
  } catch {
    return [];
  }
}

function persistRecentProjects(projects: string[]) {
  try {
    globalThis.localStorage?.setItem(RECENT_PROJECTS_KEY, JSON.stringify(projects.slice(0, 10)));
  } catch {
    // 忽略本地持久化失败，避免阻断主流程。
  }
}

interface ProjectState {
  projectPath: string;
  manifest: ProjectManifest | null;
  recentProjects: string[];
  runHistory: RunRecord[];
  isDirty: boolean;
  projectId: string;
  setProjectPath: (projectPath: string) => void;
  setManifest: (manifest: ProjectManifest | null) => void;
  setRunHistory: (runHistory: RunRecord[]) => void;
  appendRunRecord: (run: RunRecord) => void;
  setDirty: (isDirty: boolean) => void;
  rememberProject: (projectPath: string) => void;
  resetProject: () => void;
  generateProjectId: () => string;
  appendLineageOperations: (ops: DataOp[]) => void;
  updateLineageRowCounts: (before: number, after: number) => void;
}

function newProjectId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `project-${Date.now()}`;
}

export const useProjectStore = create<ProjectState>((set) => ({
  projectPath: '',
  manifest: null,
  recentProjects: loadRecentProjects(),
  runHistory: [],
  isDirty: false,
  projectId: newProjectId(),
  setProjectPath: (projectPath) => set({ projectPath }),
  setManifest: (manifest) => set({ manifest }),
  setRunHistory: (runHistory) => set({ runHistory }),
  appendRunRecord: (run) => set((state) => ({
    runHistory: [run, ...state.runHistory.filter((item) => item.run_id !== run.run_id)],
  })),
  setDirty: (isDirty) => set({ isDirty }),
  rememberProject: (projectPath) => set((state) => {
    const recentProjects = [projectPath, ...state.recentProjects.filter((item) => item !== projectPath)].slice(0, 10);
    persistRecentProjects(recentProjects);
    return { recentProjects };
  }),
  resetProject: () => set({
    projectPath: '',
    manifest: null,
    runHistory: [],
    isDirty: false,
    projectId: newProjectId(),
  }),
  generateProjectId: () => {
    const id = newProjectId();
    set({ projectId: id });
    return id;
  },
  appendLineageOperations: (ops) => set((state) => {
    if (!state.manifest) return state;
    const lineage = state.manifest.data_lineage ?? {
      source_dataset: state.manifest.source_dataset,
      active_dataset: state.manifest.active_dataset,
      operations: [],
      notes: [],
    };
    const existingOps = lineage.operations ?? [];
    // 转换为可序列化格式
    const newOps = ops.map((op) => ({ op: op.op, args: op.args }));
    return {
      manifest: {
        ...state.manifest,
        data_lineage: {
          ...lineage,
          operations: [...existingOps, ...newOps],
        },
      },
      isDirty: true,
    };
  }),
  updateLineageRowCounts: (before, after) => set((state) => {
    if (!state.manifest?.data_lineage) return state;
    return {
      manifest: {
        ...state.manifest,
        data_lineage: {
          ...state.manifest.data_lineage,
          row_count_before: before,
          row_count_after: after,
        },
      },
    };
  }),
}));
