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

## 3) Argo 相关变量

可选设置：

- `ARGO_DOMAIN`
- `ARGO_TOKEN`

若设置 `ARGO_TOKEN`，脚本会自动为应用写入 argo 相关环境变量。

## 4) 注意事项

- 请先确保账户配额满足部署要求
- 批量部署会逐项确认，避免误操作
- 建议将凭据放入 CI Secret 或安全凭据管理器
