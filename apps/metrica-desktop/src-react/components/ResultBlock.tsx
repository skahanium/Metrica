import React from 'react';
import { Button, Typography } from 'antd';
import { CopyOutlined } from '@ant-design/icons';
import { GlanceTable } from './GlanceTable';
import { TidyTable } from './TidyTable';
import { DiscreteGlanceCards } from './DiscreteGlanceCards';
import { DIDResultCards } from './DIDResultCards';
import { TreatmentEffectSummary } from './TreatmentEffectSummary';
import { EventStudyPlot } from './EventStudyPlot';
import { BalanceTable } from './BalanceTable';
import { OddsRatioTable } from './OddsRatioTable';
import { DEFFSummary } from './DEFFSummary';
import { StrataSummary } from './StrataSummary';
import { SurveyDesignPanel } from './SurveyDesignPanel';
import { GmmDiagnosticsPanel } from './GmmDiagnosticsPanel';
import { QuantileSummaryPanel } from './QuantileSummaryPanel';
import { NlsDiagnosticsPanel } from './NlsDiagnosticsPanel';
import { ThresholdSummaryPanel } from './ThresholdSummaryPanel';
import { SystemEquationsPanel } from './SystemEquationsPanel';
import { VolatilitySummaryPanel } from './VolatilitySummaryPanel';
import { SpatialDiagnosticsPanel } from './SpatialDiagnosticsPanel';
import { DurationDiagnosticsPanel } from './DurationDiagnosticsPanel';
import { ModelCapabilitiesPanel } from './ModelCapabilitiesPanel';
import type { GmmDiagnostics, ModelResult, QuantileDiagnostics, NlsDiagnostics, ThresholdDiagnostics, VolatilityDiagnostics, SpatialDiagnostics, DurationDiagnostics } from '../types/protocol';

const { Text } = Typography;

interface ResultBlockProps {
  command: string;
  /** 与 Runtime run 对齐，供事件研究图导出注册 */
  runId?: string;
  result: ModelResult;
}

export const ResultBlock: React.FC<ResultBlockProps> = ({ command, result, runId }) => {
  const modelType = result.glance?.model;
  const isDiscrete = ['logit', 'probit', 'poisson', 'ordered_logit', 'multinomial_logit', 'negbin'].includes(modelType || '');
  const isSurvey = typeof modelType === 'string' && modelType.startsWith('survey_');

  const showGmmDiagnostics =
    modelType === 'gmm_linear' || modelType === 'dynamic_panel_gmm';
  const gmmDiagnostics = showGmmDiagnostics ? (result.diagnostics as GmmDiagnostics | undefined) : undefined;

  const showQuantileSummary = modelType === 'quantile';
  const quantileDiagnostics = showQuantileSummary
    ? (result.diagnostics as QuantileDiagnostics | undefined)
    : undefined;

  const showNlsDiagnostics = modelType === 'nls';
  const nlsDiagnostics = showNlsDiagnostics
    ? (result.diagnostics as NlsDiagnostics | undefined)
    : undefined;

  const showThresholdSummary = modelType === 'threshold';
  const thresholdDiagnostics = showThresholdSummary
    ? (result.diagnostics as ThresholdDiagnostics | undefined)
    : undefined;

  const showVolatilitySummary =
    typeof modelType === 'string' && (/^ARCH\(/i.test(modelType) || /^GARCH\(/i.test(modelType));
  const volatilityDiagnostics = showVolatilitySummary
    ? (result.diagnostics as VolatilityDiagnostics | undefined)
    : undefined;

  const showSpatialDiagnostics = modelType === 'spatial_lag' || modelType === 'spatial_error' || modelType === 'spatial_slx';
  const spatialDiagnostics = showSpatialDiagnostics
    ? (result.diagnostics as SpatialDiagnostics | undefined)
    : undefined;

  const showDurationDiagnostics = modelType === 'duration_cox';
  const durationDiagnostics = showDurationDiagnostics
    ? (result.diagnostics as DurationDiagnostics | undefined)
    : undefined;

  const showSystemEquations =
    modelType === 'sur' || modelType === 'system_2sls' || modelType === 'system_3sls';

  const handleCopy = () => {
    navigator.clipboard.writeText(command).catch(() => {});
  };

  return (
    <div style={{ marginBottom: 16, background: 'var(--m-surface)', borderRadius: 8, border: '1px solid var(--m-border)', padding: 16 }}>
      {/* Command header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <Text code style={{ fontSize: 13 }}>&gt; {command}</Text>
        <Button size="small" icon={<CopyOutlined />} onClick={handleCopy} />
      </div>

      {/* Model content — 所有子组件通过 props 接收 result */}
      {result.glance && <GlanceTable result={result} />}
      {showQuantileSummary && result.glance && (
        <QuantileSummaryPanel glance={result.glance} diagnostics={quantileDiagnostics} />
      )}
      {showNlsDiagnostics && <NlsDiagnosticsPanel diagnostics={nlsDiagnostics} />}
      {showThresholdSummary && <ThresholdSummaryPanel diagnostics={thresholdDiagnostics} />}
      {showVolatilitySummary && <VolatilitySummaryPanel diagnostics={volatilityDiagnostics} />}
      {showSystemEquations && <SystemEquationsPanel result={result} />}
      {showSpatialDiagnostics && <SpatialDiagnosticsPanel diagnostics={spatialDiagnostics} />}
      {showDurationDiagnostics && (
        <DurationDiagnosticsPanel
          diagnostics={durationDiagnostics}
          hazardRatios={result.hazard_ratios}
        />
      )}
      {isDiscrete && <DiscreteGlanceCards result={result} />}
      {modelType === 'did' && <DIDResultCards result={result} />}
      {(modelType === 'ipw' || modelType === 'psm' || modelType === 'aipw') && <TreatmentEffectSummary result={result} />}
      {isDiscrete && (result.odds_ratios || (result as any).irr_entries) && <OddsRatioTable result={result} />}
      {showGmmDiagnostics && gmmDiagnostics && <GmmDiagnosticsPanel diagnostics={gmmDiagnostics} />}
      {result.tidy && result.tidy.length > 0 && <TidyTable result={result} />}
      {isSurvey && (
        <>
          <SurveyDesignPanel result={result} />
          <DEFFSummary result={result} />
          <StrataSummary result={result} />
        </>
      )}
      {modelType === 'event_study' && <EventStudyPlot result={result} runId={runId ?? null} />}
      {modelType === 'psm' && <BalanceTable result={result} />}
      {result.model_capabilities && (
        <ModelCapabilitiesPanel capabilities={result.model_capabilities} />
      )}
    </div>
  );
};
