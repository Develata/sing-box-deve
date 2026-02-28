# SAP 使用说明

本文说明如何通过 `sing-box-deve` 使用 SAP Cloud Foundry 模式。

## 1) 单账号部署

准备变量：

```bash
export SAP_CF_API="https://api.cf.eu10.hana.ondemand.com"
export SAP_CF_USERNAME="your_email"
export SAP_CF_PASSWORD="your_password"
export SAP_CF_ORG="your_org"
export SAP_CF_SPACE="your_space"
export SAP_APP_NAME="your_app_name"
export SAP_DOCKER_IMAGE="ygkkk/argosbx"
```

执行：

```bash
./sing-box-deve.sh install --provider sap --profile full --engine sing-box --protocols vless-reality,vmess-ws
```

## 2) 多账号批量部署

使用 `examples/sap-accounts.json` 填写后：

```bash
export SAP_ACCOUNTS_JSON="$(cat examples/sap-accounts.json)"
./sing-box-deve.sh install --provider sap --profile full --engine sing-box --protocols vless-reality
```

支持使用 `region` 字段代替 `api`，脚本会自动解析为对应的 API 端点。

## 3) SAP 30 Region 对照表

| 代码 | 区域 | CF API 端点 |
|------|------|-------------|
| SG | 新加坡 (Azure) | `api.cf.ap21.hana.ondemand.com` |
| US | 美国 (AWS) | `api.cf.us10-001.hana.ondemand.com` |
| AU-A | 澳洲 (AWS) | `api.cf.ap10.hana.ondemand.com` |
| SG-A | 新加坡 (AWS) | `api.cf.ap11.hana.ondemand.com` |
| KR-A | 韩国 (AWS) | `api.cf.ap12.hana.ondemand.com` |
| BR-A | 巴西 (AWS) | `api.cf.br10.hana.ondemand.com` |
| CA-A | 加拿大 (AWS) | `api.cf.ca10.hana.ondemand.com` |
| DE-A | 德国 (AWS) | `api.cf.eu10-005.hana.ondemand.com` |
| JP-A | 日本 (AWS) | `api.cf.jp10.hana.ondemand.com` |
| US-V-A | 美东弗吉尼亚 (AWS) | `api.cf.us10-001.hana.ondemand.com` |
| US-O-A | 美西俄勒冈 (AWS) | `api.cf.us11.hana.ondemand.com` |
| AU-G | 澳洲 (GCP) | `api.cf.ap30.hana.ondemand.com` |
| BR-G | 巴西 (GCP) | `api.cf.br30.hana.ondemand.com` |
| US-G | 美国 (GCP) | `api.cf.us30.hana.ondemand.com` |
| DE-G | 德国 (GCP) | `api.cf.eu30.hana.ondemand.com` |
| JP-O-G | 日本大阪 (GCP) | `api.cf.jp30.hana.ondemand.com` |
| JP-T-G | 日本东京 (GCP) | `api.cf.jp31.hana.ondemand.com` |
| IL-G | 以色列 (GCP) | `api.cf.il30.hana.ondemand.com` |
| IN-G | 印度 (GCP) | `api.cf.in30.hana.ondemand.com` |
| SA-G | 沙特 (GCP) | `api.cf.sa31.hana.ondemand.com` |
| AU-M | 澳洲 (Azure) | `api.cf.ap20.hana.ondemand.com` |
| BR-M | 巴西 (Azure) | `api.cf.br20.hana.ondemand.com` |
| CA-M | 加拿大 (Azure) | `api.cf.ca20.hana.ondemand.com` |
| US-V-M | 美东弗吉尼亚 (Azure) | `api.cf.us21.hana.ondemand.com` |
| US-W-M | 美西华盛顿 (Azure) | `api.cf.us20.hana.ondemand.com` |
| NL-M | 荷兰 (Azure) | `api.cf.eu20-001.hana.ondemand.com` |
| JP-M | 日本 (Azure) | `api.cf.jp20.hana.ondemand.com` |
| SG-M | 新加坡 (Azure) | `api.cf.ap21.hana.ondemand.com` |
| AE-N | 阿联酋 (Neo) | `api.cf.neo-ae1.hana.ondemand.com` |
| SA-N | 沙特 (Neo) | `api.cf.neo-sa1.hana.ondemand.com` |

## 4) GitHub Actions 部署

项目已提供两个 GitHub Actions 工作流：

- **main.yml** — SAP 多账号部署 + 保活（设置 `CF_USERNAMES` / `CF_PASSWORDS` / `REGIONS` 等环境变量）
- **mainh.yml** — 仅保活，检查已部署应用并自动重启

> ⚠️ 工作流必须在**私有仓库**中运行！

## 5) Argo 相关变量

可选设置：

- `ARGO_DOMAIN`
- `ARGO_TOKEN`

若设置 `ARGO_TOKEN`，脚本会自动为应用写入 argo 相关环境变量。

## 6) 注意事项

- 请先确保账户配额满足部署要求
- 批量部署会逐项确认，避免误操作
- 建议将凭据放入 CI Secret 或安全凭据管理器
- 使用 `region` 字段时，脚本会自动查表转换为 API 端点
