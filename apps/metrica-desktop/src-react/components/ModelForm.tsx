import { Form, Select, Input, Card, Tag, Typography } from 'antd';
import { useModelStore } from '../stores/modelStore';
import { useAppStore } from '../stores/appStore';
import { useDatasetStore } from '../stores/datasetStore';
import { useProjectStore } from '../stores/projectStore';
import { fitModel } from '../services/runtimeClient';

const MODEL_TYPE_LABELS: Record<string, { label: string; family: 'linear' | 'panel' | 'discrete' | 'causal' | 'timeseries' | 'survey' }> = {
  ols: { label: 'OLS / WLS', family: 'linear' },
  iv: { label: 'IV / 2SLS', family: 'linear' },
  gls: { label: 'GLS', family: 'linear' },
  panel: { label: 'Panel', family: 'panel' },
  logit: { label: 'Logit', family: 'discrete' },
  probit: { label: 'Probit', family: 'discrete' },
  poisson: { label: 'Poisson', family: 'discrete' },
  ordered_logit: { label: '有序 Logit', family: 'discrete' },
  multinomial_logit: { label: '多项 Logit', family: 'discrete' },
  negbin: { label: '负二项回归', family: 'discrete' },
  did: { label: 'DID 双重差分', family: 'causal' },
  event_study: { label: '事件研究', family: 'causal' },
  ipw: { label: 'IPW 逆概率加权', family: 'causal' },
  psm: { label: 'PSM 倾向得分匹配', family: 'causal' },
  aipw: { label: 'AIPW 双重稳健', family: 'causal' },
  arima: { label: 'ARIMA', family: 'timeseries' },
  var: { label: 'VAR', family: 'timeseries' },
  unitroot: { label: '单位根检验', family: 'timeseries' },
  cointegration: { label: '协整检验', family: 'timeseries' },
  survey_ols: { label: 'Survey OLS', family: 'survey' },
  survey_logit: { label: 'Survey Logit', family: 'survey' },
  survey_probit: { label: 'Survey Probit', family: 'survey' },
  survey_poisson: { label: 'Survey Poisson', family: 'survey' },
};

export function ModelForm() {
  const {
    modelType, setModelType, formula, setFormula,
    vcovType, setVcovType, weightsColumn, setWeightsColumn,
    clusterColumn, setClusterColumn,
    panelId, setPanelId, panelTime, setPanelTime,
    panelMethod, setPanelMethod, setLastResult,
    instruments, setInstruments, endogColumns, setEndogColumns,
    treatmentColumn, setTreatmentColumn, postColumn, setPostColumn,
    eventTimeColumn, setEventTimeColumn, outcomeColumn, setOutcomeColumn,
    timeColumn, setTimeColumn, tsVariable, setTsVariable, tsVariables, setTsVariables,
    orderP, setOrderP, orderD, setOrderD, orderQ, setOrderQ,
    seasonalP, seasonalD, seasonalQ, seasonalS,
    tsLags, setTsLags, tsDeterministic, setTsDeterministic,
    strataColumn, setStrataColumn, psuColumn, setPsuColumn, fpcColumn, setFpcColumn,
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
        treatmentColumn,
        postColumn,
        eventTimeColumn,
        outcomeColumn,
        timeColumn,
        tsVariable,
        tsVariables,
        orderP,
        orderD,
        orderQ,
        seasonalP,
        seasonalD,
        seasonalQ,
        seasonalS,
        tsLags,
        tsDeterministic,
        strataColumn,
        psuColumn,
        fpcColumn,
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
          <Select value={modelType} onChange={(v) => setModelType(v)} style={{ width: 130 }}>
            <Select.OptGroup label="线性模型">
              {Object.entries(MODEL_TYPE_LABELS)
                .filter(([, info]) => info.family === 'linear')
                .map(([value, info]) => (
                  <Select.Option key={value} value={value}>{info.label}</Select.Option>
                ))}
            </Select.OptGroup>
            <Select.OptGroup label="面板模型">
              {Object.entries(MODEL_TYPE_LABELS)
                .filter(([, info]) => info.family === 'panel')
                .map(([value, info]) => (
                  <Select.Option key={value} value={value}>{info.label}</Select.Option>
                ))}
            </Select.OptGroup>
            <Select.OptGroup label="离散模型">
              {Object.entries(MODEL_TYPE_LABELS)
                .filter(([, info]) => info.family === 'discrete')
                .map(([value, info]) => (
                  <Select.Option key={value} value={value}>{info.label}</Select.Option>
                ))}
            </Select.OptGroup>
            <Select.OptGroup label="因果推断">
              {Object.entries(MODEL_TYPE_LABELS)
                .filter(([, info]) => info.family === 'causal')
                .map(([value, info]) => (
                  <Select.Option key={value} value={value}>{info.label}</Select.Option>
                ))}
            </Select.OptGroup>
            <Select.OptGroup label="时间序列">
              {Object.entries(MODEL_TYPE_LABELS)
                .filter(([, info]) => info.family === 'timeseries')
                .map(([value, info]) => (
                  <Select.Option key={value} value={value}>{info.label}</Select.Option>
                ))}
            </Select.OptGroup>
            <Select.OptGroup label="复杂调查">
              {Object.entries(MODEL_TYPE_LABELS)
                .filter(([, info]) => info.family === 'survey')
                .map(([value, info]) => (
                  <Select.Option key={value} value={value}>{info.label}</Select.Option>
                ))}
            </Select.OptGroup>
          </Select>
        </Form.Item>
        <Form.Item label={(MODEL_TYPE_LABELS[modelType]?.label ?? '模型') + ' 公式'}>
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
        ) : modelType === 'did' || modelType === 'event_study' ? (
          <>
            <Form.Item label="个体列">
              <Input value={panelId} onChange={(e) => setPanelId(e.target.value)} style={{ width: 100 }} placeholder="id" />
            </Form.Item>
            <Form.Item label="时间列">
              <Input value={panelTime} onChange={(e) => setPanelTime(e.target.value)} style={{ width: 100 }} placeholder="time" />
            </Form.Item>
            <Form.Item label="处理组标识">
              <Input value={treatmentColumn} onChange={(e) => setTreatmentColumn(e.target.value)} style={{ width: 100 }} placeholder="treated" />
            </Form.Item>
            <Form.Item label="政策后标识">
              <Input value={postColumn} onChange={(e) => setPostColumn(e.target.value)} style={{ width: 100 }} placeholder="post" />
            </Form.Item>
            {modelType === 'event_study' && (
              <Form.Item label="事件时间列">
                <Input value={eventTimeColumn} onChange={(e) => setEventTimeColumn(e.target.value)} style={{ width: 100 }} placeholder="event_time" />
              </Form.Item>
            )}
          </>
        ) : modelType === 'ipw' || modelType === 'psm' || modelType === 'aipw' ? (
          <>
            <Form.Item label="处理变量">
              <Input value={treatmentColumn} onChange={(e) => setTreatmentColumn(e.target.value)} style={{ width: 100 }} placeholder="treated" />
            </Form.Item>
            <Form.Item label="结果变量">
              <Input value={outcomeColumn} onChange={(e) => setOutcomeColumn(e.target.value)} style={{ width: 100 }} placeholder="y" />
            </Form.Item>
          </>
        ) : modelType === 'arima' || modelType === 'var' || modelType === 'unitroot' || modelType === 'cointegration' ? (
          <>
            <Form.Item label="时间列" required>
              <Input value={timeColumn} onChange={(e) => setTimeColumn(e.target.value)} style={{ width: 100 }} placeholder="year" />
            </Form.Item>
            {modelType === 'arima' || modelType === 'unitroot' ? (
              <Form.Item label="变量">
                <Input value={tsVariable} onChange={(e) => setTsVariable(e.target.value)} style={{ width: 100 }} placeholder="y" />
              </Form.Item>
            ) : null}
            {modelType === 'var' || modelType === 'cointegration' ? (
              <Form.Item label="变量列表">
                <Input value={tsVariables} onChange={(e) => setTsVariables(e.target.value)} style={{ width: 160 }} placeholder="gdp, cpi, rate" />
              </Form.Item>
            ) : null}
            {modelType === 'arima' ? (
              <>
                <Form.Item label="p (AR)">
                  <Input type="number" value={orderP} onChange={(e) => setOrderP(Number(e.target.value))} style={{ width: 60 }} min={0} />
                </Form.Item>
                <Form.Item label="d (I)">
                  <Input type="number" value={orderD} onChange={(e) => setOrderD(Number(e.target.value))} style={{ width: 60 }} min={0} />
                </Form.Item>
                <Form.Item label="q (MA)">
                  <Input type="number" value={orderQ} onChange={(e) => setOrderQ(Number(e.target.value))} style={{ width: 60 }} min={0} />
                </Form.Item>
              </>
            ) : null}
            {modelType === 'var' ? (
              <Form.Item label="滞后阶数">
                <Input type="number" value={tsLags} onChange={(e) => setTsLags(Number(e.target.value))} style={{ width: 60 }} min={1} />
              </Form.Item>
            ) : null}
            {modelType === 'unitroot' || modelType === 'cointegration' ? (
              <Form.Item label="确定性项">
                <Select value={tsDeterministic} onChange={(v) => setTsDeterministic(v)} style={{ width: 100 }}>
                  <Select.Option value="constant">常数</Select.Option>
                  <Select.Option value="trend">趋势</Select.Option>
                  <Select.Option value="none">无</Select.Option>
                </Select>
              </Form.Item>
            ) : null}
          </>
        ) : modelType === 'logit' || modelType === 'probit' || modelType === 'poisson' || modelType === 'ordered_logit' || modelType === 'multinomial_logit' || modelType === 'negbin' ? (
          <>
            <Form.Item label="协方差">
              <Select value={vcovType} onChange={(v) => setVcovType(v)} style={{ width: 120 }}>
                <Select.Option value="classical">classical</Select.Option>
                <Select.Option value="HC1">HC1</Select.Option>
                <Select.Option value="cluster">cluster</Select.Option>
              </Select>
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
        ) : modelType === 'survey_ols' || modelType === 'survey_logit' || modelType === 'survey_probit' || modelType === 'survey_poisson' ? (
          <>
            <Form.Item label="抽样权重列" required>
              <Input value={weightsColumn} onChange={(e) => setWeightsColumn(e.target.value)} style={{ width: 120 }} placeholder="w" />
            </Form.Item>
            <Form.Item label="分层变量">
              <Input value={strataColumn} onChange={(e) => setStrataColumn(e.target.value)} style={{ width: 100 }} placeholder="可选" />
            </Form.Item>
            <Form.Item label="PSU">
              <Input value={psuColumn} onChange={(e) => setPsuColumn(e.target.value)} style={{ width: 100 }} placeholder="可选" />
            </Form.Item>
            <Form.Item label="FPC">
              <Input value={fpcColumn} onChange={(e) => setFpcColumn(e.target.value)} style={{ width: 100 }} placeholder="可选" />
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
