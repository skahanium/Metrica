import React from 'react';
import { Card, Row, Col } from 'antd';

interface ImpulseResponseChartProps {
  responses: number[][][];
  variableNames: string[];
  periods?: number;
}

export const ImpulseResponseChart: React.FC<ImpulseResponseChartProps> = ({
  responses,
  variableNames,
  periods = 20
}) => {
  const nVars = variableNames.length;
  const displayPeriods = Math.min(periods, responses.length);

  const width = 250;
  const height = 200;
  const margin = { top: 20, right: 20, bottom: 30, left: 40 };
  const plotWidth = width - margin.left - margin.right;
  const plotHeight = height - margin.top - margin.bottom;

  const renderSingleChart = (shockVar: number, responseVar: number) => {
    const data = responses.slice(0, displayPeriods).map(r => r[shockVar][responseVar]);

    // 计算 Y 轴范围
    const minY = Math.min(...data, 0);
    const maxY = Math.max(...data, 0);
    const yPadding = (maxY - minY) * 0.1 || 0.1;

    const xScale = (i: number) => margin.left + (i / (displayPeriods - 1)) * plotWidth;
    const yScale = (v: number) => margin.top + plotHeight - ((v - minY + yPadding) / (maxY - minY + 2 * yPadding)) * plotHeight;

    // 生成路径
    const path = data
      .map((v, i) => `${i === 0 ? 'M' : 'L'} ${xScale(i)} ${yScale(v)}`)
      .join(' ');

    // 零线
    const zeroY = yScale(0);

    return (
      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
        {/* 零线 */}
        <line
          x1={margin.left}
          y1={zeroY}
          x2={margin.left + plotWidth}
          y2={zeroY}
          stroke="#999"
          strokeWidth={1}
          strokeDasharray="3,3"
        />

        {/* 脉冲响应路径 */}
        <path
          d={path}
          fill="none"
          stroke="#1890ff"
          strokeWidth={2}
        />

        {/* X 轴 */}
        <line
          x1={margin.left}
          y1={margin.top + plotHeight}
          x2={margin.left + plotWidth}
          y2={margin.top + plotHeight}
          stroke="#000"
          strokeWidth={1}
        />

        {/* Y 轴 */}
        <line
          x1={margin.left}
          y1={margin.top}
          x2={margin.left}
          y2={margin.top + plotHeight}
          stroke="#000"
          strokeWidth={1}
        />

        {/* 标题 */}
        <text
          x={width / 2}
          y={12}
          textAnchor="middle"
          fontSize={10}
        >
          {variableNames[shockVar]} → {variableNames[responseVar]}
        </text>
      </svg>
    );
  };

  return (
    <Card title="脉冲响应函数" size="small">
      <Row gutter={[8, 8]}>
        {Array.from({ length: nVars }, (_, i) =>
          Array.from({ length: nVars }, (_, j) => (
            <Col key={`${i}-${j}`} span={24 / Math.min(nVars, 3)}>
              {renderSingleChart(i, j)}
            </Col>
          ))
        )}
      </Row>
    </Card>
  );
};

export default ImpulseResponseChart;
