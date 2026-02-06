# Serv00 使用说明

本文说明如何通过 `sing-box-deve` 使用 Serv00 模式。

## 1) 单账号远程引导

先准备环境变量：

```bash
export SERV00_HOST="s0.serv00.com"
export SERV00_USER="your_user"
export SERV00_PASS="your_pass"
```

执行：

```bash
./sing-box-deve.sh install --provider serv00 --profile lite --engine sing-box --protocols vless-reality
```

脚本会在执行前给出确认提示，按 `Y/n` 决定，回车走默认。

## 2) 多账号批量引导

使用 `examples/serv00-accounts.json` 作为模板，填好后：

```bash
export SERV00_ACCOUNTS_JSON="$(cat examples/serv00-accounts.json)"
./sing-box-deve.sh install --provider serv00 --profile lite --engine sing-box --protocols vless-reality
```

## 3) 可选自定义引导命令

默认引导命令可通过 `SERV00_BOOTSTRAP_CMD` 覆盖：

```bash
export SERV00_BOOTSTRAP_CMD='bash <(curl -Ls https://your-script-url)'
```

## 4) 注意事项

- 建议先在单账号验证后再批量执行
- 批量模式下会逐账号确认
- 账号信息建议通过 CI Secrets 或本地安全方式注入，不要明文提交
