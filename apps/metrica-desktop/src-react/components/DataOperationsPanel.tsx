import { useState } from 'react';
import { Button, Card, Form, Input, Select, Space, Typography, List, Tag } from 'antd';
import { PlusOutlined, DeleteOutlined, PlayCircleOutlined } from '@ant-design/icons';
import type { DataOp, DataOpKind } from '../types/protocol';
import { useDatasetStore } from '../stores/datasetStore';
import { useTransformStore } from '../stores/transformStore';
import { useAppStore } from '../stores/appStore';
import { executeDataOperations } from '../services/dataOperationExecutor';

const OP_OPTIONS: Array<{ value: DataOpKind; label: string }> = [
  { value: 'filter', label: '筛选 filter' },
  { value: 'generate', label: '生成变量 generate' },
  { value: 'impute_missing', label: '自动插补缺失值 impute missing' },
  { value: 'replace', label: '替换 replace' },
  { value: 'rename', label: '重命名 rename' },
  { value: 'drop', label: '删除列 drop' },
  { value: 'keep', label: '保留列 keep' },
  { value: 'sort', label: '排序 sort' },
  { value: 'merge', label: '合并 merge' },
  { value: 'reshape_long', label: '宽转长 reshape long' },
  { value: 'reshape_wide', label: '长转宽 reshape wide' },
  { value: 'collapse', label: '分组聚合 collapse' },
];

function splitList(value = ''): string[] {
  return value.split(',').map((v) => v.trim()).filter(Boolean);
}

function buildArgs(kind: DataOpKind, values: Record<string, string>) {
  if (kind === 'impute_missing') return {};
  if (kind === 'filter') return { condition: values.condition };
  if (kind === 'generate') return { name: values.name, expr: values.expr };
  if (kind === 'replace') return { col: values.col, condition: values.condition, value: values.value };
  if (kind === 'rename') return { mapping: { [values.old_name]: values.new_name } };
  if (kind === 'drop' || kind === 'keep' || kind === 'sort') return { cols: splitList(values.cols) };
  if (kind === 'merge') return { with: values.with, on: splitList(values.on), how: values.how || 'inner' };
  if (kind === 'reshape_long') return { id_cols: splitList(values.id_cols), time_col: values.time_col, stub_cols: splitList(values.stub_cols) };
  if (kind === 'reshape_wide') return { id_cols: splitList(values.id_cols), time_col: values.time_col, value_cols: splitList(values.value_cols) };
  return { by: splitList(values.by), stats: splitList(values.stats), value_cols: splitList(values.value_cols) };
}

export function DataOperationsPanel() {
  const [form] = Form.useForm();
  const [kind, setKind] = useState<DataOpKind>('filter');
  const { activePath } = useDatasetStore();
  const { operations, addOperation, removeOperation, clearOperations, isTransforming } = useTransformStore();
  const { setError } = useAppStore();

  const handleAdd = () => {
    const values = form.getFieldsValue();
    const op: DataOp = { op: kind, args: buildArgs(kind, values) };
    addOperation(op);
    form.resetFields();
  };

  const handleRun = async () => {
    if (!activePath) { setError('请先选择数据集'); return; }
    if (!operations.length) { setError('请先添加至少一个数据操作'); return; }
    try {
      await executeDataOperations({
        operations,
        commandLabel: `ui transform ${operations.map((op) => op.op).join(' -> ')}`,
        source: 'ui',
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : '数据操作失败');
    }
  };

  return (
    <Card size="small" title="数据操作链" style={{ marginBottom: 16 }}>
      <Space direction="vertical" style={{ width: '100%' }}>
        <Form form={form} layout="inline">
          <Form.Item label="操作">
            <Select value={kind} onChange={setKind} options={OP_OPTIONS} style={{ width: 180 }} />
          </Form.Item>
          {(kind === 'impute_missing') && (
            <Typography.Text type="secondary">
              自动对所有存在缺失值的列执行均值 / 中位数 / 众数插补
            </Typography.Text>
          )}
          {(kind === 'filter') && <Form.Item label="条件" name="condition"><Input placeholder="year >= 2015" style={{ width: 180 }} /></Form.Item>}
          {(kind === 'generate') && <><Form.Item label="变量" name="name"><Input placeholder="log_gdp" style={{ width: 120 }} /></Form.Item><Form.Item label="表达式" name="expr"><Input placeholder="log(gdp)" style={{ width: 180 }} /></Form.Item></>}
          {(kind === 'replace') && <><Form.Item label="列" name="col"><Input style={{ width: 100 }} /></Form.Item><Form.Item label="条件" name="condition"><Input style={{ width: 160 }} /></Form.Item><Form.Item label="值" name="value"><Input placeholder={'"new"'} style={{ width: 100 }} /></Form.Item></>}
          {(kind === 'rename') && <><Form.Item label="旧名" name="old_name"><Input style={{ width: 100 }} /></Form.Item><Form.Item label="新名" name="new_name"><Input style={{ width: 100 }} /></Form.Item></>}
          {(['drop', 'keep', 'sort'] as DataOpKind[]).includes(kind) && <Form.Item label="列" name="cols"><Input placeholder="x1, x2" style={{ width: 180 }} /></Form.Item>}
          {kind === 'merge' && <><Form.Item label="右表" name="with"><Input style={{ width: 200 }} /></Form.Item><Form.Item label="键" name="on"><Input placeholder="id, year" style={{ width: 140 }} /></Form.Item><Form.Item label="方式" name="how"><Select defaultValue="inner" style={{ width: 100 }} options={['inner', 'left', 'right', 'outer'].map((v) => ({ value: v, label: v }))} /></Form.Item></>}
          {kind === 'reshape_long' && <><Form.Item label="ID" name="id_cols"><Input placeholder="country" style={{ width: 120 }} /></Form.Item><Form.Item label="时间列" name="time_col"><Input placeholder="year" style={{ width: 100 }} /></Form.Item><Form.Item label="stub" name="stub_cols"><Input placeholder="gdp" style={{ width: 120 }} /></Form.Item></>}
          {kind === 'reshape_wide' && <><Form.Item label="ID" name="id_cols"><Input placeholder="country" style={{ width: 120 }} /></Form.Item><Form.Item label="时间列" name="time_col"><Input placeholder="year" style={{ width: 100 }} /></Form.Item><Form.Item label="值列" name="value_cols"><Input placeholder="gdp" style={{ width: 120 }} /></Form.Item></>}
          {kind === 'collapse' && <><Form.Item label="分组" name="by"><Input placeholder="country" style={{ width: 120 }} /></Form.Item><Form.Item label="统计" name="stats"><Input placeholder="mean, sum" style={{ width: 140 }} /></Form.Item><Form.Item label="值列" name="value_cols"><Input placeholder="gdp" style={{ width: 120 }} /></Form.Item></>}
          <Button icon={<PlusOutlined />} onClick={handleAdd}>添加</Button>
        </Form>
        <List
          size="small"
          dataSource={operations}
          locale={{ emptyText: '尚未添加操作' }}
          renderItem={(op, index) => (
            <List.Item actions={[<Button key="delete" aria-label={`删除第 ${index + 1} 步`} size="small" icon={<DeleteOutlined />} onClick={() => removeOperation(index)} />]}>
              <Typography.Text><Tag>{index + 1}</Tag>{op.op} {JSON.stringify(op.args)}</Typography.Text>
            </List.Item>
          )}
        />
        <Space>
          <Button type="primary" icon={<PlayCircleOutlined />} loading={isTransforming} onClick={handleRun}>运行数据操作</Button>
          <Button onClick={clearOperations}>清空操作链</Button>
        </Space>
      </Space>
    </Card>
  );
}
