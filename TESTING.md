# setup-dev-env.sh 测试文档

## 测试环境

```bash
docker build -t wsl-dev-test .
docker run -it --rm wsl-dev-test
```

测试完毕后清理：

```bash
docker rmi wsl-dev-test && docker builder prune -f
```

---

## TC-01: 语法检查

**验收标准**：脚本无语法错误

```bash
bash -n setup-dev-env.sh && echo "PASS" || echo "FAIL"
```

---

## TC-02: 一键安装（默认 Sheldon + Starship）

**验收标准**：

- [ ] 所有基础组件安装成功（zsh, sheldon, starship, autosuggestions, fast-syntax-highlighting, fzf-tab, zsh-completions）
- [ ] 所有可选组件安装成功（fzf, zoxide, rustup, eza, yazi, volta, uv, proto）
- [ ] `.zshrc` 包含标记块 `>>> one-click-dev-env >>>`
- [ ] `.zshrc` 包含 `eval "$(sheldon source)"`
- [ ] `.zshrc` 包含 `eval "$(starship init zsh)"`
- [ ] `.zshrc` 包含历史配置 `HISTSIZE=50000`
- [ ] `plugins.toml` 存在且包含 compinit、fzf-tab、zsh-completions、custom-completions
- [ ] 补全文件已生成到 `~/.zsh/completions/_proto` 等
- [ ] 无 `source oh-my-zsh.sh` 行

```bash
bash setup-dev-env.sh --install

# 验证
echo "--- Sheldon ---"
command -v sheldon && echo "PASS: sheldon" || echo "FAIL: sheldon"
command -v starship && echo "PASS: starship" || echo "FAIL: starship"
command -v fzf && echo "PASS: fzf" || echo "FAIL: fzf"
[[ -f "$HOME/.local/bin/zoxide" ]] && echo "PASS: zoxide" || echo "FAIL: zoxide"

echo "--- plugins.toml ---"
grep -q "compinit" ~/.config/sheldon/plugins.toml && echo "PASS: compinit" || echo "FAIL: compinit"
grep -q "fzf-tab" ~/.config/sheldon/plugins.toml && echo "PASS: fzf-tab" || echo "FAIL: fzf-tab"
grep -q "zsh-completions" ~/.config/sheldon/plugins.toml && echo "PASS: zsh-completions" || echo "FAIL: zsh-completions"
grep -q "custom-completions" ~/.config/sheldon/plugins.toml && echo "PASS: custom-completions" || echo "FAIL: custom-completions"

echo "--- .zshrc ---"
grep -q "one-click-dev-env" ~/.zshrc && echo "PASS: marker" || echo "FAIL: marker"
grep -q 'eval "$(sheldon source)"' ~/.zshrc && echo "PASS: sheldon source" || echo "FAIL: sheldon source"
grep -q 'eval "$(starship init zsh)"' ~/.zshrc && echo "PASS: starship init" || echo "FAIL: starship init"
grep -q "HISTSIZE=50000" ~/.zshrc && echo "PASS: history" || echo "FAIL: history"
! grep -q "source.*oh-my-zsh.sh" ~/.zshrc && echo "PASS: no omz" || echo "FAIL: omz残留"

echo "--- completions ---"
[[ -d "$HOME/.zsh/completions" ]] && echo "PASS: comp dir" || echo "FAIL: comp dir"
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
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k

# 验证
echo "--- OMZ ---"
[[ -d "$HOME/.oh-my-zsh" ]] && echo "PASS: omz dir" || echo "FAIL: omz dir"
grep -q "source.*oh-my-zsh.sh" ~/.zshrc && echo "PASS: omz source" || echo "FAIL: omz source"
grep -q "fzf-tab" ~/.zshrc && echo "PASS: fzf-tab in plugins" || echo "FAIL: fzf-tab"
grep -q "zsh-completions" ~/.zshrc && echo "PASS: zsh-completions in plugins" || echo "FAIL: zsh-completions"
grep -q "p10k" ~/.zshrc && echo "PASS: p10k config" || echo "FAIL: p10k"
! grep -q 'eval "$(sheldon source)"' ~/.zshrc && echo "PASS: no sheldon" || echo "FAIL: sheldon残留"

echo "--- completions ---"
[[ -d "$HOME/.oh-my-zsh/completions" ]] && echo "PASS: omz comp dir" || echo "FAIL: omz comp dir"
```

---

## TC-04: 插件管理器切换 Sheldon → Oh My Zsh

**验收标准**：

- [ ] 切换后 `.zshrc` 无 `eval "$(sheldon source)"` 行
- [ ] 切换后 `.zshrc` 有 `source oh-my-zsh.sh` 行
- [ ] 切换后标记块主题为 p10k（非 starship）

```bash
# 先安装 Sheldon + Starship
bash setup-dev-env.sh --install --plugin-mgr sheldon --theme starship

# 再切换到 OMZ + p10k
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k

# 验证
echo "--- 切换后 ---"
! grep -q 'eval "$(sheldon source)"' ~/.zshrc && echo "PASS: sheldon清除" || echo "FAIL: sheldon残留"
! grep -q "^export ZSH=" ~/.zshrc | head -1
grep -q "source.*oh-my-zsh.sh" ~/.zshrc && echo "PASS: omz恢复" || echo "FAIL: omz缺失"
grep -q "p10k" ~/.zshrc && echo "PASS: p10k主题" || echo "FAIL: p10k缺失"
! grep -q 'eval "$(starship init zsh)"' ~/.zshrc && echo "PASS: starship清除" || echo "FAIL: starship残留"
```

---

## TC-05: 插件管理器切换 Oh My Zsh → Sheldon

**验收标准**：

- [ ] 切换后 `.zshrc` 有 `eval "$(sheldon source)"`
- [ ] 切换后 `.zshrc` 无 `source oh-my-zsh.sh`、`export ZSH=`、`plugins=(` 等 OMZ 模板行
- [ ] `plugins.toml` 存在且完整

```bash
# 先安装 OMZ + p10k
bash setup-dev-env.sh --install --plugin-mgr ohmyzsh --theme p10k

# 再切换到 Sheldon + Starship
bash setup-dev-env.sh --install --plugin-mgr sheldon --theme starship

# 验证
echo "--- 切换后 ---"
grep -q 'eval "$(sheldon source)"' ~/.zshrc && echo "PASS: sheldon加载" || echo "FAIL: sheldon缺失"
! grep -q "source.*oh-my-zsh.sh" ~/.zshrc && echo "PASS: omz清除" || echo "FAIL: omz残留"
! grep -q "^export ZSH=" ~/.zshrc && echo "PASS: ZSH变量清除" || echo "FAIL: ZSH变量残留"
! grep -q "^plugins=(" ~/.zshrc && echo "PASS: plugins清除" || echo "FAIL: plugins残留"
grep -q 'eval "$(starship init zsh)"' ~/.zshrc && echo "PASS: starship主题" || echo "FAIL: starship缺失"
[[ -f "$HOME/.config/sheldon/plugins.toml" ]] && echo "PASS: plugins.toml" || echo "FAIL: plugins.toml缺失"
```

---

## TC-06: 幂等性验证

**验收标准**：重复执行脚本不产生副作用（无报错、配置无重复）

```bash
bash setup-dev-env.sh --install
bash setup-dev-env.sh --install

# 验证标记块不重复
count=$(grep -c "one-click-dev-env >>>" ~/.zshrc)
[[ "$count" -eq 1 ]] && echo "PASS: 标记块唯一" || echo "FAIL: 标记块重复($count)"
```

---

## TC-07: 部分组件安装

**验收标准**：仅安装指定的可选组件，基础组件始终安装

```bash
bash setup-dev-env.sh --install --components volta uv

# 验证
command -v volta && echo "PASS: volta" || echo "FAIL: volta"
command -v uv && echo "PASS: uv" || echo "FAIL: uv"
! command -v proto && echo "PASS: proto未安装" || echo "FAIL: proto不应安装"
command -v zsh && echo "PASS: zsh(基础)" || echo "FAIL: zsh"
command -v sheldon && echo "PASS: sheldon(基础)" || echo "FAIL: sheldon"
```

---

## TC-08: 一键卸载

**验收标准**：

- [ ] 所有组件被移除
- [ ] `.zshrc` 中的标记块被清除
- [ ] 不影响标记块外的用户配置

```bash
# 先在标记块外添加用户配置
echo "# MY_CUSTOM_CONFIG=true" >> ~/.zshrc
bash setup-dev-env.sh --install
bash setup-dev-env.sh --uninstall

# 验证
! command -v sheldon && echo "PASS: sheldon卸载" || echo "FAIL: sheldon残留"
! grep -q "one-click-dev-env" ~/.zshrc && echo "PASS: 标记块清除" || echo "FAIL: 标记块残留"
grep -q "MY_CUSTOM_CONFIG" ~/.zshrc && echo "PASS: 用户配置保留" || echo "FAIL: 用户配置丢失"
```

---

## TC-09: 主题切换

**验收标准**：切换主题后配置正确更新

```bash
# Starship → p10k
bash setup-dev-env.sh --install --theme starship
bash setup-dev-env.sh --install --theme p10k

grep -q "p10k" ~/.zshrc && echo "PASS: p10k配置" || echo "FAIL: p10k缺失"
! grep -q 'eval "$(starship init zsh)"' ~/.zshrc && echo "PASS: starship清除" || echo "FAIL: starship残留"
```

---

## TC-10: 帮助信息

**验收标准**：`--help` 输出帮助并退出

```bash
bash setup-dev-env.sh --help | grep -q "可选值" && echo "PASS" || echo "FAIL"
```
