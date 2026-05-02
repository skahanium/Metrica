import { create } from 'zustand';
import type { ModelResult, ModelSpec } from '../types/protocol';

interface ModelState {
  modelType: 'ols' | 'panel';
  formula: string;
  vcovType: string;
  weightsColumn: string;
  clusterColumn: string;
  panelId: string;
  panelTime: string;
  panelMethod: 'fe' | 're' | 'fd' | 'between';
  lastResult: ModelResult | null;
  setModelType: (t: 'ols' | 'panel') => void;
  setFormula: (f: string) => void;
  setVcovType: (v: string) => void;
  setWeightsColumn: (w: string) => void;
  setClusterColumn: (c: string) => void;
  setPanelId: (id: string) => void;
  setPanelTime: (t: string) => void;
  setPanelMethod: (m: 'fe' | 're' | 'fd' | 'between') => void;
  setLastResult: (r: ModelResult | null) => void;
  buildModelSpec: () => ModelSpec;
}

export const useModelStore = create<ModelState>((set, get) => ({
  modelType: 'ols',
  formula: 'y ~ x1 + x2',
  vcovType: 'classical',
  weightsColumn: '',
  clusterColumn: '',
  panelId: '',
  panelTime: '',
  panelMethod: 'fe',
  lastResult: null,
  setModelType: (modelType) => set({ modelType }),
  setFormula: (formula) => set({ formula }),
  setVcovType: (vcovType) => set({ vcovType }),
  setWeightsColumn: (weightsColumn) => set({ weightsColumn }),
  setClusterColumn: (clusterColumn) => set({ clusterColumn }),
  setPanelId: (panelId) => set({ panelId }),
  setPanelTime: (panelTime) => set({ panelTime }),
  setPanelMethod: (panelMethod) => set({ panelMethod }),
  setLastResult: (lastResult) => set({ lastResult }),
  buildModelSpec: () => {
    const s = get();
    const spec: ModelSpec = {
      model_type: s.modelType,
      formula: s.formula,
    };
    if (s.modelType === 'panel') {
      spec.panel_id = s.panelId;
      spec.panel_time = s.panelTime;
      spec.panel_method = s.panelMethod;
    } else {
      spec.vcov = { type: s.vcovType };
      if (s.weightsColumn.trim()) spec.weights = s.weightsColumn.trim();
      if (s.clusterColumn.trim()) spec.cluster_column = s.clusterColumn.trim();
    }
    return spec;
  },
}));
