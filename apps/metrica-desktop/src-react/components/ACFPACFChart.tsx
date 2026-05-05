import React from 'react';
import { Card, Row, Col } from 'antd';

interface ACFPACFChartProps {
  acfValues: number[];
  pacfValues: number[];
  maxLags?: number;
}

export const ACFPACFChart: React.FC<ACFPACFChartProps> = ({
  acfValues,
  pacfValues,
  maxLags = 20
}) => {
  const displayLags = Math.min(maxLags, acfValues.length - 1);

  const width = 350;
  const height = 250;
  const margin = { top: 30, right: 20, bottom: 40, left: 50 };
  const plotWidth = width - margin.left - margin.right;
  const plotHeight = height - margin.top - margin.bottom;

  // 置信区间边界（95%）— 使用 Bartlett 公式 1.96 / sqrt(n)
  const confidenceBound = 1.96 / Math.sqrt(acfValues.length);

  const renderBarChart = (values: number[], title: string) => {
    const barWidth = plotWidth / (displayLags + 1) * 0.8;

    const yScale = (v: number) => margin.top + plotHeight / 2 - (v * plotHeight / 2.5);
    const zeroY = yScale(0);

    return (
      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
        {/* 标题 */}
        <text
          x={width / 2}
          y={15}
          textAnchor="middle"
          fontSize={12}
          fontWeight="bold"
        >
          {title}
        </text>

        {/* 置信区间上界 */}
        <line
          x1={margin.left}
          y1={yScale(confidenceBound)}
          x2={margin.left + plotWidth}
          y2={yScale(confidenceBound)}
          stroke="#ff4d4f"
          strokeWidth={1}
          strokeDasharray="3,3"
        />

        {/* 置信区间下界 */}
        <line
          x1={margin.left}
          y1={yScale(-confidenceBound)}
          x2={margin.left + plotWidth}
          y2={yScale(-confidenceBound)}
          stroke="#ff4d4f"
          strokeWidth={1}
          strokeDasharray="3,3"
        />

        {/* 零线 */}
        <line
          x1={margin.left}
          y1={zeroY}
          x2={margin.left + plotWidth}
          y2={zeroY}
          stroke="#000"
          strokeWidth={1}
        />

        {/* 柱状图 */}
        {values.slice(1, displayLags + 1).map((v, i) => {
          const x = margin.left + (i + 0.5) * (plotWidth / (displayLags + 1));
          const barHeight = Math.abs(v) * plotHeight / 2.5;
          const y = v >= 0 ? zeroY - barHeight : zeroY;

          return (
            <rect
              key={i}
              x={x - barWidth / 2}
              y={y}
              width={barWidth}
              height={barHeight}
              fill={Math.abs(v) > confidenceBound ? '#1890ff' : '#999'}
            />
          );
        })}

        {/* X 轴 */}
        <line
          x1={margin.left}
          y1={margin.top + plotHeight}
          x2={margin.left + plotWidth}
          y2={margin.top + plotHeight}
          stroke="#000"
          strokeWidth={1}
        />

        {/* X 轴标签 */}
        {Array.from({ length: Math.min(displayLags, 10) }, (_, i) => {
          const lagIndex = Math.floor(i * displayLags / 10);
          const x = margin.left + (lagIndex + 0.5) * (plotWidth / (displayLags + 1));
          return (
            <text
              key={i}
              x={x}
              y={margin.top + plotHeight + 15}
              textAnchor="middle"
              fontSize={10}
            >
              {lagIndex + 1}
            </text>
          );
        })}

        {/* X 轴标题 */}
        <text
          x={margin.left + plotWidth / 2}
          y={height - 5}
          textAnchor="middle"
          fontSize={10}
        >
          滞后阶数
        </text>
      </svg>
    );
  };

  return (
    <Card title="自相关与偏自相关函数" size="small">
      <Row gutter={16}>
        <Col span={12}>
          {renderBarChart(acfValues, 'ACF (自相关)')}
        </Col>
        <Col span={12}>
          {renderBarChart(pacfValues, 'PACF (偏自相关)')}
        </Col>
      </Row>
    </Card>
  );
};

export default ACFPACFChart;
