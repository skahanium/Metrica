export function modelControlState(modelType) {
  const isPanel = modelType === "panel";

  return {
    isPanel,
    olsHidden: isPanel,
    panelHidden: !isPanel,
    formulaLabel: isPanel ? "面板公式" : "OLS 公式",
  };
}

export function applyModelControlState({
  modelType,
  olsOptions,
  panelOptions,
  formulaLabel,
}) {
  const state = modelControlState(modelType);

  if (olsOptions) {
    olsOptions.hidden = state.olsHidden;
  }
  if (panelOptions) {
    panelOptions.hidden = state.panelHidden;
  }
  if (formulaLabel) {
    formulaLabel.textContent = state.formulaLabel;
  }

  return state;
}
