import { create } from 'zustand';
import type { ModelSpec, ModelResult } from '../types/protocol';

interface ModelHistoryEntry {
  id: string;
  label: string;
  runId: string;
  modelType: ModelSpec['model_type'];
  formula: string;
  datasetPath: string;
  result: ModelResult;
  createdAt: string;
  command: string;
}

interface ModelState {
  modelType: ModelSpec['model_type'];
  formula: string;
  vcovType: string;
  weights: string;
  weightsColumn: string;
  clusterColumn: string;
  panelId: string;
  panelTime: string;
  panelMethod: string;
  instruments: string;
  endogColumns: string;
  treatmentColumn: string;
  postColumn: string;
  eventTimeColumn: string;
  outcomeColumn: string;
  timeColumn: string;
  tsVariable: string;
  tsVariables: string;
  orderP: number;
  orderD: number;
  orderQ: number;
  seasonalP: number;
  seasonalD: number;
  seasonalQ: number;
  seasonalS: number;
  tsLags: number;
  tsDeterministic: string;
  tsMethod: string;
  strataColumn: string;
  psuColumn: string;
  fpcColumn: string;
  lastResult: ModelResult | null;
  modelHistory: ModelHistoryEntry[];
  selectedModelIds: Set<string>;
  setModelType: (t: ModelSpec['model_type']) => void;
  setFormula: (f: string) => void;
  setVcovType: (v: string) => void;
  setWeights: (w: string) => void;
  setWeightsColumn: (w: string) => void;
  setClusterColumn: (c: string) => void;
  setPanelId: (id: string) => void;
  setPanelTime: (t: string) => void;
  setPanelMethod: (m: string) => void;
  setInstruments: (i: string) => void;
  setEndogColumns: (c: string) => void;
  setTreatmentColumn: (c: string) => void;
  setPostColumn: (c: string) => void;
  setEventTimeColumn: (c: string) => void;
  setOutcomeColumn: (c: string) => void;
  setTimeColumn: (c: string) => void;
  setTsVariable: (v: string) => void;
  setTsVariables: (v: string) => void;
  setOrderP: (p: number) => void;
  setOrderD: (d: number) => void;
  setOrderQ: (q: number) => void;
  setSeasonalP: (p: number) => void;
  setSeasonalD: (d: number) => void;
  setSeasonalQ: (q: number) => void;
  setSeasonalS: (s: number) => void;
  setTsLags: (l: number) => void;
  setTsDeterministic: (d: string) => void;
  setTsMethod: (m: string) => void;
  setStrataColumn: (c: string) => void;
  setPsuColumn: (c: string) => void;
  setFpcColumn: (c: string) => void;
  setLastResult: (r: ModelResult | null) => void;
  addToHistory: (entry: ModelHistoryEntry) => void;
  removeFromHistory: (id: string) => void;
  clearHistory: () => void;
  setSelectedModelIds: (ids: string[]) => void;
  toggleModelSelection: (id: string) => void;
  applyModelSpec: (spec: Partial<ModelSpec>) => void;
}

export const useModelStore = create<ModelState>((set) => ({
  modelType: 'ols',
  formula: '',
  vcovType: 'classical',
  weights: '',
  weightsColumn: '',
  clusterColumn: '',
  panelId: '',
  panelTime: '',
  panelMethod: 'fe',
  instruments: '',
  endogColumns: '',
  treatmentColumn: '',
  postColumn: '',
  eventTimeColumn: '',
  outcomeColumn: '',
  timeColumn: '',
  tsVariable: '',
  tsVariables: '',
  orderP: 1, orderD: 0, orderQ: 0,
  seasonalP: 0, seasonalD: 0, seasonalQ: 0, seasonalS: 0,
  tsLags: 2,
  tsDeterministic: 'constant',
  tsMethod: 'mle',
  strataColumn: '',
  psuColumn: '',
  fpcColumn: '',
  lastResult: null,
  modelHistory: [],
  selectedModelIds: new Set<string>(),

  setModelType: (modelType) => set({ modelType }),
  setFormula: (formula) => set({ formula }),
  setVcovType: (vcovType) => set({ vcovType }),
  setWeights: (weights) => set({ weights }),
  setWeightsColumn: (weightsColumn) => set({ weightsColumn }),
  setClusterColumn: (clusterColumn) => set({ clusterColumn }),
  setPanelId: (panelId) => set({ panelId }),
  setPanelTime: (panelTime) => set({ panelTime }),
  setPanelMethod: (panelMethod) => set({ panelMethod }),
  setInstruments: (instruments) => set({ instruments }),
  setEndogColumns: (endogColumns) => set({ endogColumns }),
  setTreatmentColumn: (treatmentColumn) => set({ treatmentColumn }),
  setPostColumn: (postColumn) => set({ postColumn }),
  setEventTimeColumn: (eventTimeColumn) => set({ eventTimeColumn }),
  setOutcomeColumn: (outcomeColumn) => set({ outcomeColumn }),
  setTimeColumn: (timeColumn) => set({ timeColumn }),
  setTsVariable: (tsVariable) => set({ tsVariable }),
  setTsVariables: (tsVariables) => set({ tsVariables }),
  setOrderP: (orderP) => set({ orderP }),
  setOrderD: (orderD) => set({ orderD }),
  setOrderQ: (orderQ) => set({ orderQ }),
  setSeasonalP: (seasonalP) => set({ seasonalP }),
  setSeasonalD: (seasonalD) => set({ seasonalD }),
  setSeasonalQ: (seasonalQ) => set({ seasonalQ }),
  setSeasonalS: (seasonalS) => set({ seasonalS }),
  setTsLags: (tsLags) => set({ tsLags }),
  setTsDeterministic: (tsDeterministic) => set({ tsDeterministic }),
  setTsMethod: (tsMethod) => set({ tsMethod }),
  setStrataColumn: (strataColumn) => set({ strataColumn }),
  setPsuColumn: (psuColumn) => set({ psuColumn }),
  setFpcColumn: (fpcColumn) => set({ fpcColumn }),
  setLastResult: (lastResult) => set({ lastResult }),
  addToHistory: (entry) => set((state) => ({
    modelHistory: [entry, ...state.modelHistory],
  })),
  removeFromHistory: (id) => set((state) => ({
    modelHistory: state.modelHistory.filter((e) => e.id !== id),
  })),
  clearHistory: () => set({ modelHistory: [] }),
  setSelectedModelIds: (ids) => set({ selectedModelIds: new Set(ids) }),
  toggleModelSelection: (id) => set((state) => {
    const next = new Set(state.selectedModelIds);
    if (next.has(id)) next.delete(id); else next.add(id);
    return { selectedModelIds: next };
  }),
  applyModelSpec: (spec) => set((state) => {
    const p = spec.params ?? {};
    return {
      modelType: (spec.model_type as ModelState['modelType']) ?? state.modelType,
      formula: spec.formula ?? state.formula,
      vcovType: spec.vcov?.type ?? state.vcovType,
      weights: spec.weights ?? state.weights,
      weightsColumn: (p.weights_column as string | undefined) ?? state.weightsColumn,
      clusterColumn: spec.cluster_column ?? state.clusterColumn,
      panelId: (p.panel_id as string | undefined) ?? state.panelId,
      panelTime: (p.panel_time as string | undefined) ?? state.panelTime,
      panelMethod: (p.panel_method as ModelState['panelMethod']) ?? state.panelMethod,
      instruments: Array.isArray(p.instruments) ? p.instruments.join(', ') : state.instruments,
      endogColumns: Array.isArray(p.endog_columns) ? p.endog_columns.join(', ') : state.endogColumns,
      treatmentColumn: (p.treatment_column as string | undefined) ?? state.treatmentColumn,
      strataColumn: (p.strata_column as string | undefined) ?? state.strataColumn,
      psuColumn: (p.psu_column as string | undefined) ?? state.psuColumn,
      fpcColumn: (p.fpc_column as string | undefined) ?? state.fpcColumn,
    };
  }),
}));
