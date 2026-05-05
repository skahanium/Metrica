import { create } from 'zustand';
import type { ModelResult, ModelSpec } from '../types/protocol';

export interface ModelHistoryItem {
  id: string;
  label: string;
  runId: string;
  modelType: string;
  formula: string;
  datasetPath: string;
  result: ModelResult;
  createdAt: string;
}

interface ModelState {
  modelType: 'ols' | 'iv' | 'gls' | 'panel' | 'logit' | 'probit' | 'poisson' | 'ordered_logit' | 'multinomial_logit' | 'negbin' | 'did' | 'event_study' | 'ipw' | 'psm' | 'aipw' | 'survey_ols' | 'survey_logit' | 'survey_probit' | 'survey_poisson';
  formula: string;
  vcovType: string;
  weightsColumn: string;
  clusterColumn: string;
  panelId: string;
  panelTime: string;
  panelMethod: 'fe' | 're' | 'fd' | 'between' | 'hdfde' | 'cre' | 'panel_iv';
  instruments: string;
  endogColumns: string;
  treatmentColumn: string;
  strataColumn: string;
  psuColumn: string;
  fpcColumn: string;
  lastResult: ModelResult | null;
  modelHistory: ModelHistoryItem[];
  selectedModelIds: string[];
  setModelType: (t: ModelState['modelType']) => void;
  setFormula: (f: string) => void;
  setVcovType: (v: string) => void;
  setWeightsColumn: (w: string) => void;
  setClusterColumn: (c: string) => void;
  setPanelId: (id: string) => void;
  setPanelTime: (t: string) => void;
  setPanelMethod: (m: 'fe' | 're' | 'fd' | 'between' | 'hdfde' | 'cre' | 'panel_iv') => void;
  setInstruments: (v: string) => void;
  setEndogColumns: (v: string) => void;
  setTreatmentColumn: (v: string) => void;
  setStrataColumn: (v: string) => void;
  setPsuColumn: (v: string) => void;
  setFpcColumn: (v: string) => void;
  setLastResult: (r: ModelResult | null) => void;
  addToHistory: (item: ModelHistoryItem) => void;
  removeFromHistory: (id: string) => void;
  clearHistory: () => void;
  setSelectedModelIds: (ids: string[]) => void;
  toggleModelSelection: (id: string) => void;
  applyModelSpec: (spec: Partial<ModelSpec>) => void;
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
  instruments: '',
  endogColumns: '',
  treatmentColumn: '',
  strataColumn: '',
  psuColumn: '',
  fpcColumn: '',
  lastResult: null,
  modelHistory: [],
  selectedModelIds: [],
  setModelType: (modelType) => set({ modelType }),
  setFormula: (formula) => set({ formula }),
  setVcovType: (vcovType) => set({ vcovType }),
  setWeightsColumn: (weightsColumn) => set({ weightsColumn }),
  setClusterColumn: (clusterColumn) => set({ clusterColumn }),
  setPanelId: (panelId) => set({ panelId }),
  setPanelTime: (panelTime) => set({ panelTime }),
  setPanelMethod: (panelMethod) => set({ panelMethod }),
  setInstruments: (instruments) => set({ instruments }),
  setEndogColumns: (endogColumns) => set({ endogColumns }),
  setTreatmentColumn: (treatmentColumn) => set({ treatmentColumn }),
  setStrataColumn: (strataColumn) => set({ strataColumn }),
  setPsuColumn: (psuColumn) => set({ psuColumn }),
  setFpcColumn: (fpcColumn) => set({ fpcColumn }),
  setLastResult: (lastResult) => set({ lastResult }),
  addToHistory: (item) => set((state) => ({
    modelHistory: [item, ...state.modelHistory.filter((h) => h.id !== item.id)].slice(0, 20),
  })),
  removeFromHistory: (id) => set((state) => ({
    modelHistory: state.modelHistory.filter((h) => h.id !== id),
    selectedModelIds: state.selectedModelIds.filter((i) => i !== id),
  })),
  clearHistory: () => set({ modelHistory: [], selectedModelIds: [] }),
  setSelectedModelIds: (selectedModelIds) => set({ selectedModelIds }),
  toggleModelSelection: (id) => set((state) => ({
    selectedModelIds: state.selectedModelIds.includes(id)
      ? state.selectedModelIds.filter((i) => i !== id)
      : [...state.selectedModelIds, id],
  })),
  applyModelSpec: (spec) => set((state) => ({
    modelType: (spec.model_type as ModelState['modelType']) ?? state.modelType,
    formula: spec.formula ?? state.formula,
    vcovType: spec.vcov?.type ?? state.vcovType,
    weightsColumn: spec.weights ?? state.weightsColumn,
    clusterColumn: spec.cluster_column ?? state.clusterColumn,
    panelId: spec.panel_id ?? state.panelId,
    panelTime: spec.panel_time ?? state.panelTime,
    panelMethod: (spec.panel_method as ModelState['panelMethod']) ?? state.panelMethod,
    instruments: spec.instruments?.join(', ') ?? state.instruments,
    endogColumns: spec.endog_columns?.join(', ') ?? state.endogColumns,
    treatmentColumn: spec.treatment_column ?? state.treatmentColumn,
    strataColumn: spec.strata_column ?? state.strataColumn,
    psuColumn: spec.psu_column ?? state.psuColumn,
    fpcColumn: spec.fpc_column ?? state.fpcColumn,
  })),
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
      if (s.panelMethod === 'panel_iv') {
        if (s.instruments.trim()) spec.instruments = s.instruments.split(',').map((v) => v.trim()).filter(Boolean);
        if (s.endogColumns.trim()) spec.endog_columns = s.endogColumns.split(',').map((v) => v.trim()).filter(Boolean);
      }
    } else if (s.modelType === 'iv') {
      spec.vcov = { type: s.vcovType };
      if (s.clusterColumn.trim()) spec.cluster_column = s.clusterColumn.trim();
      if (s.instruments.trim()) spec.instruments = s.instruments.split(',').map((v) => v.trim()).filter(Boolean);
      if (s.endogColumns.trim()) spec.endog_columns = s.endogColumns.split(',').map((v) => v.trim()).filter(Boolean);
    } else if (s.modelType === 'gls') {
      spec.vcov = { type: s.vcovType };
    } else if (s.modelType === 'did' || s.modelType === 'event_study') {
      spec.panel_id = s.panelId;
      spec.panel_time = s.panelTime;
      if (s.treatmentColumn.trim()) spec.treatment_column = s.treatmentColumn.trim();
    } else if (s.modelType === 'ipw' || s.modelType === 'psm' || s.modelType === 'aipw') {
      if (s.treatmentColumn.trim()) spec.treatment_column = s.treatmentColumn.trim();
    } else if (s.modelType === 'logit' || s.modelType === 'probit' || s.modelType === 'poisson' || s.modelType === 'ordered_logit' || s.modelType === 'multinomial_logit' || s.modelType === 'negbin') {
      spec.vcov = { type: s.vcovType };
    } else if (s.modelType === 'survey_ols' || s.modelType === 'survey_logit' || s.modelType === 'survey_probit' || s.modelType === 'survey_poisson') {
      spec.vcov = { type: s.vcovType };
      if (s.weightsColumn.trim()) spec.weights_column = s.weightsColumn.trim();
      if (s.strataColumn.trim()) spec.strata_column = s.strataColumn.trim();
      if (s.psuColumn.trim()) spec.psu_column = s.psuColumn.trim();
      if (s.fpcColumn.trim()) spec.fpc_column = s.fpcColumn.trim();
    } else {
      spec.vcov = { type: s.vcovType };
      if (s.weightsColumn.trim()) spec.weights = s.weightsColumn.trim();
      if (s.clusterColumn.trim()) spec.cluster_column = s.clusterColumn.trim();
    }
    return spec;
  },
}));
