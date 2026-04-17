# setup-dev-env.sh 测试文档

## 测试环境

```bash
# 构建
docker build -t wsl-dev-test .

# 运行（TUN 模式或可直连环境，使用 --network host）
docker run -it --rm --network host wsl-dev-test

# 运行（HTTP 代理模式）
docker run -it --rm \
  -e http_proxy=http://host.docker.internal:10809 \
  -e https_proxy=http://host.docker.internal:10809 \
  wsl-dev-test

# 清理
docker rmi wsl-dev-test && docker builder prune -f
```

> **注意**：Dockerfile 已将 apt 源切换到 USTC 镜像，apt-get 无需代理即可下载。

---

## 验证方法约定

所有安装后的验证统一使用 `zsh -c 'source ~/.zshrc && ...'`，确保 PATH 和环境变量与用户实际使用一致。

安装日志使用 `grep -E` 过滤关键行实时输出，避免 `tail` 管道阻塞。

---

## TC-01: 语法检查

**验收标准**：脚本无语法错误

```bash
bash -n setup-dev-env.sh && echo "PASS" || echo "FAIL"
```

---

## TC-02: 一键安装（默认 Sheldon + Starship，全组件）

**验收标准**：

- [ ] 所有基础组件安装成功
- [ ] 所有可选组件安装成功
- [ ] `plugins.toml` 包含 compinit、fzf-tab、zsh-completions、custom-completions
- [ ] `.zshrc` 标记块完整（sheldon source、starship、history）
- [ ] 补全文件生成到 `~/.zsh/completions/`

```bash
docker run --rm --network host wsl-dev-test bash -c '
bash setup-dev-env.sh --install 2>&1 | grep -E "^\[|^══" | head -60

echo ""
echo "========== TC-02 VALIDATION =========="
zsh -c "source ~/.zshrc 2>/dev/null
echo \"--- components ---\"
command -v sheldon && echo \"PASS: sheldon\" || echo \"FAIL: sheldon\"
command -v starship && echo \"PASS: starship\" || echo \"FAIL: starship\"
command -v fzf && echo \"PASS: fzf\" || echo \"FAIL: fzf\"
command -v zoxide && echo \"PASS: zoxide\" || echo \"FAIL: zoxide\"
command -v rustup && echo \"PASS: rustup\" || echo \"FAIL: rustup\"
command -v eza && echo \"PASS: eza\" || echo \"FAIL: eza\"
command -v yazi && echo \"PASS: yazi\" || echo \"FAIL: yazi\"
command -v volta && echo \"PASS: volta\" || echo \"FAIL: volta\"
command -v uv && echo \"PASS: uv\" || echo \"FAIL: uv\"
command -v proto && echo \"PASS: proto\" || echo \"FAIL: proto\"

echo \"--- plugins.toml ---\"
grep -q compinit ~/.config/sheldon/plugins.toml && echo \"PASS: compinit\" || echo \"FAIL: compinit\"
grep -q fzf-tab ~/.config/sheldon/plugins.toml && echo \"PASS: fzf-tab\" || echo \"FAIL: fzf-tab\"
grep -q zsh-completions ~/.config/sheldon/plugins.toml && echo \"PASS: zsh-completions\" || echo \"FAIL: zsh-completions\"
grep -q custom-completions ~/.config/sheldon/plugins.toml && echo \"PASS: custom-completions\" || echo \"FAIL: custom-completions\"

echo \"--- .zshrc ---\"
grep -q one-click-dev-env ~/.zshrc && echo \"PASS: marker\" || echo \"FAIL: marker\"
grep -q \"sheldon source\" ~/.zshrc && echo \"PASS: sheldon source\" || echo \"FAIL: sheldon source\"
grep -q \"starship init zsh\" ~/.zshrc && echo \"PASS: starship init\" || echo \"FAIL: starship init\"
grep -q HISTSIZE=50000 ~/.zshrc && echo \"PASS: history\" || echo \"FAIL: history\"
! grep -q \"source.*oh-my-zsh.sh\" ~/.zshrc && echo \"PASS: no omz\" || echo \"FAIL: omz残留\"

echo \"--- completions ---\"
[[ -d ~/.zsh/completions ]] && echo \"PASS: comp dir\" || echo \"FAIL: comp dir\"
ls ~/.zsh/completions/ 2>/dev/null
"
'
```

---

## TC-03: 一键安装（Oh My Zsh + Powerlevel10k）

**验收标准**：

- [ ] OMZ 安装到 `~/.oh-my-zsh`
- [ ] `.zshrc` 包含 `source $ZSH/oh-my-zsh.sh`
- [ ] `.zshrc` 的 plugins 列表包含 fzf-tab、zsh-completions
- [ ] `.zshrc` 标记块包含 p10k 配置
- [ ] 补全文件生成到 `~/.oh-my-zsh/completions/`
- [ ] 无 `eval "$(sheldon source)"` 行

```bash
docker run --rm --network host wsl-dev-test bash -c '
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k --components fzf,zoxide,volta,uv,proto 2>&1 | grep -E "^\[|^══" | head -40

zsh -c "source ~/.zshrc 2>/dev/null
echo \"--- OMZ ---\"
[[ -d ~/.oh-my-zsh ]] && echo \"PASS: omz dir\" || echo \"FAIL: omz dir\"
grep -q \"source.*oh-my-zsh.sh\" ~/.zshrc && echo \"PASS: omz source\" || echo \"FAIL: omz source\"
grep -q fzf-tab ~/.zshrc && echo \"PASS: fzf-tab in plugins\" || echo \"FAIL: fzf-tab\"
grep -q zsh-completions ~/.zshrc && echo \"PASS: zsh-completions in plugins\" || echo \"FAIL: zsh-completions\"
grep -q p10k ~/.zshrc && echo \"PASS: p10k config\" || echo \"FAIL: p10k\"
! grep -q \"sheldon source\" ~/.zshrc && echo \"PASS: no sheldon\" || echo \"FAIL: sheldon残留\"

echo \"--- completions ---\"
[[ -d ~/.oh-my-zsh/completions ]] && echo \"PASS: omz comp dir\" || echo \"FAIL: omz comp dir\"
ls ~/.oh-my-zsh/completions/ 2>/dev/null
"
'
```

---

## TC-04: 插件管理器切换 Sheldon → Oh My Zsh

**验收标准**：切换后 `.zshrc` 无 sheldon 残留，OMZ 模板恢复

```bash
docker run --rm --network host wsl-dev-test bash -c '
bash setup-dev-env.sh --install --plugin-mgr sheldon --theme starship --components fzf 2>&1 | grep -E "^\[OK\]|^══" | tail -5
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k --components fzf 2>&1 | grep -E "^\[OK\]|^══" | tail -5

zsh -c "source ~/.zshrc 2>/dev/null
echo \"--- 切换后 ---\"
! grep -q \"sheldon source\" ~/.zshrc && echo \"PASS: sheldon清除\" || echo \"FAIL: sheldon残留\"
grep -q \"source.*oh-my-zsh.sh\" ~/.zshrc && echo \"PASS: omz恢复\" || echo \"FAIL: omz缺失\"
grep -q p10k ~/.zshrc && echo \"PASS: p10k主题\" || echo \"FAIL: p10k缺失\"
! grep -q \"starship init zsh\" ~/.zshrc && echo \"PASS: starship清除\" || echo \"FAIL: starship残留\"
"
'
```

---

## TC-05: 插件管理器切换 Oh My Zsh → Sheldon

**验收标准**：切换后 `.zshrc` 无 OMZ 模板残留，sheldon 加载正常

```bash
docker run --rm --network host wsl-dev-test bash -c '
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k --components fzf 2>&1 | grep -E "^\[OK\]|^══" | tail -5
bash setup-dev-env.sh --install --plugin-mgr sheldon --theme starship --components fzf 2>&1 | grep -E "^\[OK\]|^══" | tail -5

zsh -c "source ~/.zshrc 2>/dev/null
echo \"--- 切换后 ---\"
grep -q \"sheldon source\" ~/.zshrc && echo \"PASS: sheldon加载\" || echo \"FAIL: sheldon缺失\"
! grep -q \"source.*oh-my-zsh.sh\" ~/.zshrc && echo \"PASS: omz清除\" || echo \"FAIL: omz残留\"
! grep -q \"^export ZSH=\" ~/.zshrc && echo \"PASS: ZSH变量清除\" || echo \"FAIL: ZSH变量残留\"
! grep -q \"^plugins=(\" ~/.zshrc && echo \"PASS: plugins清除\" || echo \"FAIL: plugins残留\"
grep -q \"starship init zsh\" ~/.zshrc && echo \"PASS: starship主题\" || echo \"FAIL: starship缺失\"
[[ -f ~/.config/sheldon/plugins.toml ]] && echo \"PASS: plugins.toml\" || echo \"FAIL: plugins.toml缺失\"
"
'
```

---

## TC-06: 幂等性验证

**验收标准**：重复执行脚本不产生副作用（无报错、标记块无重复）

```bash
docker run --rm --network host wsl-dev-test bash -c '
bash setup-dev-env.sh --install --components fzf,zoxide 2>&1 | grep -E "^\[|^══" | tail -5
bash setup-dev-env.sh --install --components fzf,zoxide 2>&1 | grep -E "^\[|^══" | tail -5

count=$(grep -c "one-click-dev-env >>>" ~/.zshrc)
[[ "$count" -eq 1 ]] && echo "PASS: 标记块唯一" || echo "FAIL: 标记块重复($count)"
'
```

---

## TC-07: 部分组件安装

**验收标准**：仅安装指定的可选组件，基础组件始终安装

```bash
docker run --rm --network host wsl-dev-test bash -c '
bash setup-dev-env.sh --install --components volta,uv 2>&1 | grep -E "^\[|^══" | tail -10

zsh -c "source ~/.zshrc 2>/dev/null
command -v volta && echo \"PASS: volta\" || echo \"FAIL: volta\"
command -v uv && echo \"PASS: uv\" || echo \"FAIL: uv\"
! command -v proto && echo \"PASS: proto未安装\" || echo \"FAIL: proto不应安装\"
command -v zsh && echo \"PASS: zsh(基础)\" || echo \"FAIL: zsh\"
command -v sheldon && echo \"PASS: sheldon(基础)\" || echo \"FAIL: sheldon\"
"
'
```

---

## TC-08: 一键卸载

**验收标准**：所有组件被移除，`.zshrc` 标记块被清除，用户自定义配置保留

```bash
docker run --rm --network host wsl-dev-test bash -c '
echo "# MY_CUSTOM_CONFIG=true" >> ~/.zshrc
bash setup-dev-env.sh --install --components fzf,zoxide 2>&1 | grep -E "^\[|^══" | tail -5
bash setup-dev-env.sh --uninstall 2>&1 | grep -E "^\[|^══" | tail -10

! command -v sheldon && echo "PASS: sheldon卸载" || echo "FAIL: sheldon残留"
! grep -q "one-click-dev-env" ~/.zshrc && echo "PASS: 标记块清除" || echo "FAIL: 标记块残留"
grep -q "MY_CUSTOM_CONFIG" ~/.zshrc && echo "PASS: 用户配置保留" || echo "FAIL: 用户配置丢失"
'
```

---

## TC-09: 主题切换

**验收标准**：切换主题后配置正确更新

```bash
docker run --rm --network host wsl-dev-test bash -c '
bash setup-dev-env.sh --install --theme starship --components fzf 2>&1 | grep -E "^\[OK\]" | tail -3
bash setup-dev-env.sh --install --theme p10k --components fzf 2>&1 | grep -E "^\[OK\]" | tail -3

grep -q "p10k" ~/.zshrc && echo "PASS: p10k配置" || echo "FAIL: p10k缺失"
! grep -q "starship init zsh" ~/.zshrc && echo "PASS: starship清除" || echo "FAIL: starship残留"
'
```

---

## TC-10: 帮助信息

**验收标准**：`--help` 输出帮助并退出

```bash
bash setup-dev-env.sh --help | grep -q "可选值" && echo "PASS" || echo "FAIL"
```
