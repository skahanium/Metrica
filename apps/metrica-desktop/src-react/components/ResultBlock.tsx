import React, { useState } from 'react';
import { Button, Space, Typography } from 'antd';
import { ReloadOutlined, CopyOutlined } from '@ant-design/icons';
import { TeachingLayer } from './TeachingLayer';
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
import type { ModelResult } from '../types/protocol';

const { Text } = Typography;

interface ResultBlockProps {
  command: string;
  result: ModelResult;
  teachingEnabled: boolean;
  onRerun: (command: string) => void;
}

export const ResultBlock: React.FC<ResultBlockProps> = ({ command, result, teachingEnabled: _teachingEnabled, onRerun }) => {
  const [showTeaching, setShowTeaching] = useState(false);
  const modelType = result.glance?.model;
  const isDiscrete = ['logit', 'probit', 'poisson', 'ordered_logit', 'multinomial_logit', 'negbin'].includes(modelType || '');
  const isSurvey = typeof modelType === 'string' && modelType.startsWith('survey_');

  const handleCopy = () => {
    navigator.clipboard.writeText(command).catch(() => {});
  };

  return (
    <div style={{ marginBottom: 16, background: '#fff', borderRadius: 8, border: '1px solid #f0f0f0', padding: 16 }}>
      {/* Command header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <Text code style={{ fontSize: 13 }}>&gt; {command}</Text>
        <Space>
          <Button size="small" icon={<ReloadOutlined />} onClick={() => onRerun(command)} />
          <Button size="small" icon={<CopyOutlined />} onClick={handleCopy} />
          <Button
            size="small"
            type={showTeaching ? 'primary' : 'default'}
            onClick={() => setShowTeaching(!showTeaching)}
          >
            教学
          </Button>
        </Space>
      </div>

      {/* Teaching layer - 按钮切换，局部状态控制 */}
      {showTeaching && <TeachingLayer result={result} />}

      {/* Model content — 所有子组件通过 props 接收 result */}
      {result.glance && <GlanceTable result={result} />}
      {isDiscrete && <DiscreteGlanceCards result={result} />}
      {modelType === 'did' && <DIDResultCards result={result} />}
      {(modelType === 'ipw' || modelType === 'psm' || modelType === 'aipw') && <TreatmentEffectSummary result={result} />}
      {isDiscrete && (result.odds_ratios || (result as any).irr_entries) && <OddsRatioTable result={result} />}
      {result.tidy && result.tidy.length > 0 && <TidyTable result={result} />}
      {isSurvey && (
        <>
          <SurveyDesignPanel result={result} />
          <DEFFSummary result={result} />
          <StrataSummary result={result} />
        </>
      )}
      {modelType === 'event_study' && <EventStudyPlot result={result} />}
      {modelType === 'psm' && <BalanceTable result={result} />}
    </div>
  );
};
