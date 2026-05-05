import React from 'react';
import { Card } from 'antd';

interface ForecastChartProps {
  historical: number[];
  forecast: {
    point_forecast: number[];
    lower_bound: number[];
    upper_bound: number[];
  };
  title?: string;
}

export const ForecastChart: React.FC<ForecastChartProps> = ({
  historical,
  forecast,
  title = '预测图'
}) => {
  const historicalLength = historical.length;
  const forecastLength = forecast.point_forecast.length;
  const totalLength = historicalLength + forecastLength;

  // 计算 Y 轴范围
  const allValues = [
    ...historical,
    ...forecast.point_forecast,
    ...forecast.lower_bound,
    ...forecast.upper_bound
  ];
  const minY = Math.min(...allValues);
  const maxY = Math.max(...allValues);
  const yPadding = (maxY - minY) * 0.1;

  // 简单的 SVG 图表实现
  const width = 800;
  const height = 400;
  const margin = { top: 40, right: 40, bottom: 60, left: 60 };
  const plotWidth = width - margin.left - margin.right;
  const plotHeight = height - margin.top - margin.bottom;

  const xScale = (i: number) => margin.left + (i / (totalLength - 1)) * plotWidth;
  const yScale = (v: number) => margin.top + plotHeight - ((v - minY + yPadding) / (maxY - minY + 2 * yPadding)) * plotHeight;

  // 生成历史数据路径
  const historicalPath = historical
    .map((v, i) => `${i === 0 ? 'M' : 'L'} ${xScale(i)} ${yScale(v)}`)
    .join(' ');

  // 生成预测数据路径
  const forecastPath = forecast.point_forecast
    .map((v, i) => `${i === 0 ? 'M' : 'L'} ${xScale(historicalLength + i)} ${yScale(v)}`)
    .join(' ');

  // 生成置信区间路径
  const upperPath = forecast.upper_bound
    .map((v, i) => `${i === 0 ? 'M' : 'L'} ${xScale(historicalLength + i)} ${yScale(v)}`)
    .join(' ');
  const lowerPath = forecast.lower_bound
    .reverse()
    .map((v, i) => `${i === 0 ? 'L' : 'L'} ${xScale(historicalLength + forecastLength - 1 - i)} ${yScale(v)}`)
    .join(' ');

  return (
    <Card title={title} size="small">
      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
        {/* 置信区间 */}
        <path
          d={`${upperPath} ${lowerPath} Z`}
          fill="rgba(24, 144, 255, 0.2)"
          stroke="none"
        />

        {/* 历史数据线 */}
        <path
          d={historicalPath}
          fill="none"
          stroke="#1890ff"
          strokeWidth={2}
        />

        {/* 预测数据线 */}
        <path
          d={forecastPath}
          fill="none"
          stroke="#ff4d4f"
          strokeWidth={2}
          strokeDasharray="5,5"
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

        {/* 分隔线 */}
        <line
          x1={xScale(historicalLength - 0.5)}
          y1={margin.top}
          x2={xScale(historicalLength - 0.5)}
          y2={margin.top + plotHeight}
          stroke="#999"
          strokeWidth={1}
          strokeDasharray="3,3"
        />

        {/* 图例 */}
        <g transform={`translate(${margin.left + 10}, ${margin.top + 10})`}>
          <line x1={0} y1={0} x2={20} y2={0} stroke="#1890ff" strokeWidth={2} />
          <text x={25} y={4} fontSize={12}>历史数据</text>

          <line x1={0} y1={20} x2={20} y2={20} stroke="#ff4d4f" strokeWidth={2} strokeDasharray="5,5" />
          <text x={25} y={24} fontSize={12}>预测值</text>

          <rect x={0} y={35} width={20} height={10} fill="rgba(24, 144, 255, 0.2)" />
          <text x={25} y={44} fontSize={12}>95% 置信区间</text>
        </g>

        {/* X 轴标签 */}
        <text
          x={margin.left + plotWidth / 2}
          y={height - 10}
          textAnchor="middle"
          fontSize={12}
        >
          时间
        </text>

        {/* Y 轴标签 */}
        <text
          x={15}
          y={margin.top + plotHeight / 2}
          textAnchor="middle"
          fontSize={12}
          transform={`rotate(-90, 15, ${margin.top + plotHeight / 2})`}
        >
          值
        </text>
      </svg>
    </Card>
  );
};

export default ForecastChart;
