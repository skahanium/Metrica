import { Form, Select, Input, Card, Tag, Typography } from 'antd';
import { useModelStore } from '../stores/modelStore';
import { useAppStore } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useProjectStore } from '../stores/projectStore';
import { fitModel } from '../services/runtimeClient';

export function ModelForm() {
  const {
    modelType, setModelType, formula, setFormula,
    vcovType, setVcovType, weightsColumn, setWeightsColumn,
    clusterColumn, setClusterColumn,
    panelId, setPanelId, panelTime, setPanelTime,
    panelMethod, setPanelMethod, setLastResult,
    instruments, setInstruments, endogColumns, setEndogColumns,
  } = useModelStore();
  const { setLoading, setError } = useAppStore();
  const activePath = useDatasetStore((s) => s.activePath);
  const isDerived = useDatasetStore((s) => s.sourcePath !== s.activePath);
  const { appendRunRecord, setDirty } = useProjectStore();

  const handleRun = async () => {
    if (!activePath) { setError('请先选择数据集'); return; }
    setLoading(true);
    setError(null);
    try {
      const { projectId } = useProjectStore.getState();
      const res = await fitModel({
        datasetPath: activePath,
        formula,
        modelType,
        vcovType,
        weightsColumn,
        clusterColumn,
        panelId,
        panelTime,
        panelMethod,
        instruments,
        endogColumns,
        projectId,
      });
      if (res.status === 'error') {
        setError(res.messages.map((m) => m.text).join('; '));
      } else if (res.result_payload) {
        setLastResult(res.result_payload);
        if (res.run_record) {
          appendRunRecord(res.run_record);
        }
        setDirty(true);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card size="small" style={{ marginBottom: 16 }}>
      <Typography.Text type="secondary" style={{ display: 'block', marginBottom: 8 }}>
        当前建模数据 <Tag color={isDerived ? 'blue' : 'default'}>{isDerived ? '派生数据' : '原始数据'}</Tag>
        {activePath || '未选择'}
      </Typography.Text>
      <Form id="model-form" layout="inline" onFinish={handleRun}>
        <Form.Item label="模型类型">
          <Select value={modelType} onChange={(v) => setModelType(v)} style={{ width: 100 }}>
            <Select.Option value="ols">OLS / WLS</Select.Option>
            <Select.Option value="iv">IV / 2SLS</Select.Option>
            <Select.Option value="gls">GLS</Select.Option>
            <Select.Option value="panel">Panel</Select.Option>
          </Select>
        </Form.Item>
        <Form.Item label={modelType === 'panel' ? '面板公式' : 'OLS 公式'}>
          <Input value={formula} onChange={(e) => setFormula(e.target.value)} style={{ width: 240 }} />
        </Form.Item>
        {modelType === 'panel' ? (
          <>
            <Form.Item label="个体列">
              <Input value={panelId} onChange={(e) => setPanelId(e.target.value)} style={{ width: 100 }} placeholder="firm" />
            </Form.Item>
            <Form.Item label="时间列">
              <Input value={panelTime} onChange={(e) => setPanelTime(e.target.value)} style={{ width: 100 }} placeholder="year" />
            </Form.Item>
            <Form.Item label="方法">
              <Select value={panelMethod} onChange={(v) => setPanelMethod(v)} style={{ width: 140 }}>
                <Select.Option value="fe">FE 固定效应</Select.Option>
                <Select.Option value="re">RE 随机效应</Select.Option>
                <Select.Option value="fd">FD 一阶差分</Select.Option>
                <Select.Option value="between">Between</Select.Option>
                <Select.Option value="hdfde">HDFE 高维固定效应</Select.Option>
                <Select.Option value="cre">CRE/Mundlak</Select.Option>
                <Select.Option value="panel_iv">Panel IV</Select.Option>
              </Select>
            </Form.Item>
            {panelMethod === 'panel_iv' && (
              <>
                <Form.Item label="工具变量">
                  <Input value={instruments} onChange={(e) => setInstruments(e.target.value)} style={{ width: 160 }} placeholder="z1, z2" />
                </Form.Item>
                <Form.Item label="内生变量">
                  <Input value={endogColumns} onChange={(e) => setEndogColumns(e.target.value)} style={{ width: 160 }} placeholder="x1" />
                </Form.Item>
              </>
            )}
          </>
        ) : modelType === 'iv' ? (
          <>
            <Form.Item label="协方差">
              <Select value={vcovType} onChange={(v) => setVcovType(v)} style={{ width: 120 }}>
                <Select.Option value="classical">classical</Select.Option>
                <Select.Option value="HC1">HC1</Select.Option>
                <Select.Option value="cluster">cluster</Select.Option>
              </Select>
            </Form.Item>
            <Form.Item label="工具变量">
              <Input value={instruments} onChange={(e) => setInstruments(e.target.value)} style={{ width: 160 }} placeholder="z1, z2" />
            </Form.Item>
            <Form.Item label="内生变量">
              <Input value={endogColumns} onChange={(e) => setEndogColumns(e.target.value)} style={{ width: 160 }} placeholder="x1" />
            </Form.Item>
            <Form.Item label="聚类列">
              <Input value={clusterColumn} onChange={(e) => setClusterColumn(e.target.value)} style={{ width: 100 }} placeholder="可选" />
            </Form.Item>
          </>
        ) : modelType === 'gls' ? (
          <>
            <Form.Item label="协方差">
              <Select value={vcovType} onChange={(v) => setVcovType(v)} style={{ width: 120 }}>
                <Select.Option value="classical">classical</Select.Option>
                <Select.Option value="HC1">HC1</Select.Option>
                <Select.Option value="cluster">cluster</Select.Option>
              </Select>
            </Form.Item>
          </>
        ) : (
          <>
            <Form.Item label="协方差">
              <Select value={vcovType} onChange={(v) => setVcovType(v)} style={{ width: 120 }}>
                <Select.Option value="classical">classical</Select.Option>
                <Select.Option value="HC1">HC1</Select.Option>
                <Select.Option value="cluster">cluster</Select.Option>
              </Select>
            </Form.Item>
            <Form.Item label="权重列">
              <Input value={weightsColumn} onChange={(e) => setWeightsColumn(e.target.value)} style={{ width: 100 }} placeholder="可选" />
            </Form.Item>
            <Form.Item label="聚类列">
              <Input value={clusterColumn} onChange={(e) => setClusterColumn(e.target.value)} style={{ width: 100 }} placeholder="可选" />
            </Form.Item>
          </>
        )}
      </Form>
    </Card>
  );
}
