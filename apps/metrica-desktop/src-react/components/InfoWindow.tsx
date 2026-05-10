import React from 'react';
import { Descriptions, Typography, Tag } from 'antd';
import { useDatasetStore } from '../stores/datasetStore';
import { useProjectStore } from '../stores/projectStore';

const { Text } = Typography;

export const InfoWindow: React.FC = () => {
  const summary = useDatasetStore((s) => s.summary);
  const sourcePath = useDatasetStore((s) => s.sourcePath);
  const activePath = useDatasetStore((s) => s.activePath);
  const selectedVariable = useDatasetStore((s) => s.selectedVariable);
  const variableMetadata = useDatasetStore((s) => s.variableMetadata);
  const getVariableByName = useDatasetStore((s) => s.getVariableByName);
  const projectPath = useProjectStore((s) => s.projectPath);

  const isDerived = sourcePath !== activePath;
  const selectedCol = selectedVariable ? getVariableByName(selectedVariable) : null;
  const selectedMeta = selectedVariable ? variableMetadata.get(selectedVariable) : null;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{ padding: '8px 12px', borderBottom: '1px solid #f0f0f0' }}>
        <Text strong style={{ fontSize: 13 }}>信息窗口</Text>
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '8px 12px' }}>
        {/* 数据集信息 */}
        <Text type="secondary" style={{ fontSize: 11, marginBottom: 4, display: 'block' }}>数据集</Text>
        {summary ? (
          <Descriptions
            column={1}
            size="small"
            labelStyle={{ fontSize: 12, color: '#8c8c8c', width: 80, paddingBottom: 2 }}
            contentStyle={{ fontSize: 12, paddingBottom: 2 }}
          >
            <Descriptions.Item label="数据来源">
              <Text style={{ fontSize: 12, wordBreak: 'break-all' }}>
                {sourcePath || '未记录'}
              </Text>
            </Descriptions.Item>
            {isDerived && (
              <Descriptions.Item label="活动数据">
                <Tag color="orange">派生数据</Tag>
                <Text style={{ fontSize: 11, wordBreak: 'break-all', display: 'block' }}>
                  {activePath}
                </Text>
              </Descriptions.Item>
            )}
            <Descriptions.Item label="变量数">{summary.ncols ?? '未记录'}</Descriptions.Item>
            <Descriptions.Item label="观测数">{summary.nrows ?? '未记录'}</Descriptions.Item>
            {projectPath && (
              <Descriptions.Item label="项目路径">
                <Text style={{ fontSize: 11, wordBreak: 'break-all' }}>{projectPath}</Text>
              </Descriptions.Item>
            )}
          </Descriptions>
        ) : (
          <Text type="secondary" style={{ fontSize: 12 }}>未加载数据</Text>
        )}

        {/* 选中变量信息 */}
        {selectedVariable && (
          <div style={{ marginTop: 16 }}>
            <Text type="secondary" style={{ fontSize: 11, marginBottom: 4, display: 'block' }}>
              选中变量
            </Text>
            {selectedCol ? (
              <Descriptions
                column={1}
                size="small"
                labelStyle={{ fontSize: 12, color: '#8c8c8c', width: 80, paddingBottom: 2 }}
                contentStyle={{ fontSize: 12, paddingBottom: 2 }}
              >
                <Descriptions.Item label="当前名称">
                  <Text strong>{selectedCol.name}</Text>
                </Descriptions.Item>
                <Descriptions.Item label="标签">
                  {selectedMeta?.label || selectedMeta?.original_name || selectedCol.name}
                </Descriptions.Item>
                <Descriptions.Item label="数据类型">
                  {selectedCol.type || '未记录'}
                </Descriptions.Item>
                <Descriptions.Item label="格式">
                  {selectedCol.inferred_type || '未记录'}
                </Descriptions.Item>
                <Descriptions.Item label="缺失数">
                  {selectedCol.missing_count !== undefined ? selectedCol.missing_count : '未记录'}
                </Descriptions.Item>
                <Descriptions.Item label="唯一值数">
                  {selectedMeta?.unique_count !== undefined ? selectedMeta.unique_count : '未记录'}
                </Descriptions.Item>
              </Descriptions>
            ) : (
              <Text type="secondary" style={{ fontSize: 12 }}>未找到变量信息</Text>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
