import { create } from 'zustand';
import type { DatasetSummary, VariableMetadata, DataHistoryNode, ColumnSummary } from '../types/protocol';

interface DatasetState {
  // 现有字段
  sourcePath: string;
  activePath: string;
  summary: DatasetSummary | null;

  // 新增字段
  variableMetadata: Map<string, VariableMetadata>;
  selectedVariable: string | null;
  dataHistory: DataHistoryNode[];
  currentHistoryIndex: number;
  browseColumns: string[] | null;
  browseReadonly: boolean;

  // 现有方法
  isDerived: () => boolean;
  setFilePath: (p: string) => void;
  setSourceAndActivePath: (sourcePath: string, activePath: string) => void;
  setActivePath: (p: string) => void;
  setSummary: (s: DatasetSummary | null) => void;
  resetDerived: () => void;

  // 新增方法
  setSelectedVariable: (name: string | null) => void;
  addVariableMetadata: (name: string, meta: VariableMetadata) => void;
  renameVariable: (oldName: string, newName: string) => void;
  addDataHistoryNode: (node: DataHistoryNode) => void;
  restoreToHistoryIndex: (index: number) => void;
  getVariableByName: (name: string) => ColumnSummary | undefined;
  setBrowseContext: (columns: string[] | null, readonly: boolean) => void;
  clearBrowseContext: () => void;
}

export const useDatasetStore = create<DatasetState>((set, get) => ({
  // 现有初始值
  sourcePath: '',
  activePath: '',
  summary: null,

  // 新增初始值
  variableMetadata: new Map(),
  selectedVariable: null,
  dataHistory: [],
  currentHistoryIndex: -1,
  browseColumns: null,
  browseReadonly: false,

  // 现有方法（保持不变）
  isDerived: () => get().sourcePath !== get().activePath,
  setFilePath: (filePath) => set({ sourcePath: filePath, activePath: filePath }),
  setSourceAndActivePath: (sourcePath, activePath) => set({ sourcePath, activePath }),
  setActivePath: (activePath) => set({ activePath }),
  setSummary: (summary) => set({ summary }),
  resetDerived: () => set((state) => ({ activePath: state.sourcePath })),

  // 新增方法实现
  setSelectedVariable: (name) => set({ selectedVariable: name }),

  addVariableMetadata: (name, meta) => set((state) => {
    const newMap = new Map(state.variableMetadata);
    newMap.set(name, meta);
    return { variableMetadata: newMap };
  }),

  renameVariable: (oldName, newName) => set((state) => {
    if (!state.summary) return state;
    const newColumns = state.summary.columns.map((col) =>
      col.name === oldName ? { ...col, name: newName } : col
    );
    const meta = state.variableMetadata.get(oldName);
    const newMetaMap = new Map(state.variableMetadata);
    if (meta) {
      newMetaMap.delete(oldName);
      newMetaMap.set(newName, { ...meta, current_name: newName });
    }
    return {
      summary: { ...state.summary, columns: newColumns },
      variableMetadata: newMetaMap,
      selectedVariable: state.selectedVariable === oldName ? newName : state.selectedVariable,
    };
  }),

  addDataHistoryNode: (node) => set((state) => ({
    dataHistory: [...state.dataHistory, node],
    currentHistoryIndex: state.dataHistory.length,
  })),

  restoreToHistoryIndex: (index) => set((state) => {
    if (index < 0 || index >= state.dataHistory.length) return state;
    const node = state.dataHistory[index];
    return {
      activePath: node.active_data_path,
      currentHistoryIndex: index,
    };
  }),

  getVariableByName: (name) => {
    const { summary } = get();
    return summary?.columns.find((col) => col.name === name);
  },

  setBrowseContext: (columns, readonly) => set({
    browseColumns: columns,
    browseReadonly: readonly,
  }),

  clearBrowseContext: () => set({
    browseColumns: null,
    browseReadonly: false,
  }),
}));
