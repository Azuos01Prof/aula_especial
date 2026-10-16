<#
.SYNOPSIS
  Prepara o laboratório "Boas práticas de Code Review" (Versionamento de Código).

.DESCRIPTION
  Atividade elaborada pelo Prof. Marcos Souza - Educação Profissional Paulista,
  Técnico em Desenvolvimento de Sistemas, Versionamento de Código,
  4º bimestre, Semana 22, Aula 2 - Boas práticas de Code Review.

  O script, sem pedir nenhuma interação:
    1. verifica Git, Node.js, npm e VS Code;
    2. cria a pasta do projeto e todos os arquivos do exercício;
    3. cria o repositório Git com a branch main (versão estável);
    4. cria a branch feature/validacao-token (a "PR" que o grupo vai revisar);
    5. roda os testes e o lint (checagens automáticas);
    6. inicia um servidor local de preview (Node.js, sem dependências);
    7. mostra um resumo do que funcionou, do que falhou e de como corrigir.

.PARAMETER Destino
  Pasta onde o projeto será criado. Padrão: Documentos\atividade-code-review
  (se já existir, cria uma pasta nova com data e hora no nome).

.PARAMETER Porta
  Porta do servidor de preview. Padrão: 8080 (se ocupada, tenta as 10 seguintes).

.PARAMETER SemServidor
  Não inicia o servidor de preview.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\atividade-code-review_script.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\atividade-code-review_script.ps1 -Destino C:\lab\grupo3 -Porta 8090
#>
[CmdletBinding()]
param(
  [string]$Destino = '',
  [int]$Porta = 8080,
  [switch]$SemServidor
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$NoWindows = ($env:OS -eq 'Windows_NT')
$Script:Base = ''
$Script:Disponivel = @{ git = $false; node = $false; npm = $false; pasta = $false; repo = $false; branch = $false }
$Script:Resultados = New-Object System.Collections.Generic.List[object]
$Utf8SemBom = New-Object System.Text.UTF8Encoding($false)
$Script:UrlPreview = $null
$Script:PidPreview = $null

# ------------------------------------------------------------------ utilitários
function Registrar {
  param([string]$Passo, [string]$Status, [string]$Detalhe = '', [string]$Correcao = '')
  $Script:Resultados.Add([pscustomobject]@{ Passo = $Passo; Status = $Status; Detalhe = $Detalhe; Correcao = $Correcao })
  $cor = @{ OK = 'Green'; ESPERADO = 'Cyan'; AVISO = 'Yellow'; FALHA = 'Red'; IGNORADO = 'DarkGray' }[$Status]
  Write-Host ('[{0,-8}] {1}' -f $Status, $Passo) -ForegroundColor $cor
  if ($Detalhe) { Write-Host ('           ' + ($Detalhe -split "`n")[0]) -ForegroundColor DarkGray }
}

function Executar-Passo {
  param([string]$Nome, [scriptblock]$Acao, [string]$Correcao, [string[]]$Requer = @())
  foreach ($r in $Requer) {
    if (-not $Script:Disponivel[$r]) {
      Registrar $Nome 'IGNORADO' "Depende de um passo anterior que falhou ($r)." "Corrija primeiro o passo relacionado a '$r' e rode o script de novo."
      return $false
    }
  }
  try {
    $detalhe = & $Acao
    Registrar $Nome 'OK' ([string]$detalhe)
    return $true
  } catch {
    Registrar $Nome 'FALHA' $_.Exception.Message $Correcao
    return $false
  }
}

function Invoke-Nativo {
  param([string]$Exe, [string[]]$Argumentos = @(), [switch]$PermitirFalha)
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $saida = & $Exe @Argumentos 2>&1 | ForEach-Object { "$_" }
    $codigo = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $eap
  }
  $texto = (@($saida) -join "`n").Trim()
  if ($codigo -ne 0 -and -not $PermitirFalha) {
    throw ("'{0} {1}' terminou com código {2}. {3}" -f $Exe, ($Argumentos -join ' '), $codigo, $texto)
  }
  return [pscustomobject]@{ Codigo = $codigo; Saida = $texto }
}

function Escrever-Arquivo {
  param([string]$Relativo, [string]$Conteudo)
  $caminho = Join-Path $Script:Base $Relativo
  $pasta = Split-Path $caminho -Parent
  if (-not (Test-Path $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
  $texto = ($Conteudo -replace "`r`n", "`n").TrimEnd("`n") + "`n"
  [System.IO.File]::WriteAllText($caminho, $texto, $Utf8SemBom)
}

function Escrever-Conjunto {
  param($Arquivos)
  foreach ($nome in $Arquivos.Keys) { Escrever-Arquivo $nome $Arquivos[$nome] }
  return $Arquivos.Count
}

function Rodar-Git { Invoke-Nativo 'git' ([string[]]$args) }

$NpmExe = 'npm'
if (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue) { $NpmExe = 'npm.cmd' }

# ------------------------------------------------------------------ conteúdo dos arquivos
# Versão estável (branch main)
$ArquivosMain = [ordered]@{
  'package.json' = @'
{
  "name": "code-review-lab",
  "version": "1.0.0",
  "description": "Laboratório de Code Review - Versionamento de Código",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test tests/token.test.js",
    "lint": "node scripts/lint.js",
    "check": "npm run lint && npm test",
    "start": "node server.cjs"
  }
}
'@
  'index.html' = @'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Validador de Token</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main class="cartao">
    <h1>Validador de Token</h1>
    <p class="dica">Formato esperado: <code>tk_</code> + 16 letras/números (ex.: <code>tk_a1b2c3d4e5f6a7b8</code>)</p>
    <label for="token">Token de acesso</label>
    <input id="token" type="text" autocomplete="off" placeholder="tk_...">
    <button id="validar" type="button">Validar</button>
    <p id="resultado" role="status"></p>
  </main>
  <script type="module" src="app.js"></script>
</body>
</html>
'@
  'style.css' = @'
* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  font-family: system-ui, "Segoe UI", sans-serif;
  background: #11161d;
  color: #e6edf3;
}
.cartao {
  width: min(420px, 92vw);
  padding: 24px;
  border: 1px solid #2d3743;
  border-radius: 10px;
  background: #161d26;
  display: grid;
  gap: 10px;
}
h1 { margin: 0; font-size: 1.4rem; }
.dica { margin: 0; color: #9aa7b4; font-size: .9rem; }
code { font-family: Consolas, monospace; color: #f0c674; }
input, button { font: inherit; padding: 10px 12px; border-radius: 6px; }
input { border: 1px solid #3a4654; background: #0d1117; color: inherit; }
button { border: 0; background: #2f81f7; color: #fff; cursor: pointer; }
button:hover { background: #1f6feb; }
#resultado { min-height: 1.4em; margin: 0; font-weight: 600; }
#resultado.ok { color: #3fb950; }
#resultado.erro { color: #f85149; }
'@
  'app.js' = @'
import { mascaraToken } from './src/token.js';

const campo = document.querySelector('#token');
const botao = document.querySelector('#validar');
const saida = document.querySelector('#resultado');

botao.addEventListener('click', () => {
  saida.textContent = 'Token informado: ' + mascaraToken(campo.value);
  saida.className = '';
});
'@
  'src/token.js' = @'
/**
 * Utilidades de token de acesso usadas pela tela de login.
 * Formato esperado: prefixo "tk_" + 16 caracteres [a-z0-9] (19 no total).
 */
export const PREFIXO = 'tk_';
export const TAMANHO = 19;

/** Remove espaços extras e padroniza para minúsculas. */
export function normalizaToken(valor) {
  if (typeof valor !== 'string') return '';
  return valor.trim().toLowerCase();
}

/** Oculta o token para exibição: tk_a1b2************ */
export function mascaraToken(valor) {
  const token = normalizaToken(valor);
  if (token.length <= 7) return token;
  return token.slice(0, 7) + '*'.repeat(token.length - 7);
}
'@
  'tests/token.test.js' = @'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizaToken, mascaraToken } from '../src/token.js';

test('normalizaToken remove espaços e padroniza minúsculas', () => {
  assert.equal(normalizaToken('  TK_ABC  '), 'tk_abc');
});

test('normalizaToken devolve vazio para valores que não são texto', () => {
  assert.equal(normalizaToken(undefined), '');
  assert.equal(normalizaToken(null), '');
});

test('mascaraToken mantém visíveis só os 7 primeiros caracteres', () => {
  assert.equal(mascaraToken('tk_a1b2c3d4e5f6a7b8'), 'tk_a1b2************');
});
'@
  'scripts/lint.js' = @'
// Checagem automática simples (sem dependências), usada no CI e localmente.
//   ERRO  -> bloqueia (código de saída 1): console.log esquecido
//   AVISO -> não bloqueia: nome de função com menos de 4 caracteres
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const arquivos = ['app.js', ...readdirSync('src')
  .filter((nome) => nome.endsWith('.js'))
  .map((nome) => join('src', nome))];

let erros = 0;
let avisos = 0;

for (const caminho of arquivos) {
  readFileSync(caminho, 'utf8').split(/\r?\n/).forEach((linha, i) => {
    const onde = `${caminho}:${i + 1}`;
    if (/console\.log\(/.test(linha)) {
      erros++;
      console.log(`ERRO  ${onde}  console.log esquecido (pode expor dados, como o token)`);
    }
    const funcao = linha.match(/function\s+([A-Za-z_$][\w$]*)/);
    if (funcao && funcao[1].length < 4) {
      avisos++;
      console.log(`AVISO ${onde}  nome de função pouco descritivo: "${funcao[1]}"`);
    }
  });
}

console.log(`\nResultado: ${erros} erro(s), ${avisos} aviso(s) em ${arquivos.length} arquivo(s).`);
process.exit(erros > 0 ? 1 : 0);
'@
  'server.cjs' = @'
// Servidor estático mínimo para pré-visualização (sem dependências).
// Uso: node server.cjs   (porta padrão 8080; se ocupada, tenta as 10 seguintes)
const http = require('http');
const fs = require('fs');
const path = require('path');

const RAIZ = __dirname;
const TIPOS = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.md': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon'
};

let porta = Number(process.env.PORT) || 8080;
const portaMaxima = porta + 10;

const servidor = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const arquivo = path.normalize(path.join(RAIZ, url === '/' ? 'index.html' : url));
  if (!arquivo.startsWith(RAIZ)) {
    res.writeHead(403);
    return res.end('Acesso negado');
  }
  fs.readFile(arquivo, (erro, dados) => {
    if (erro) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      return res.end('Não encontrado: ' + url);
    }
    res.writeHead(200, {
      'Content-Type': TIPOS[path.extname(arquivo).toLowerCase()] || 'application/octet-stream',
      'Cache-Control': 'no-store'
    });
    res.end(dados);
  });
});

servidor.on('error', (erro) => {
  if (erro.code === 'EADDRINUSE' && porta < portaMaxima) {
    porta++;
    servidor.listen(porta);
  } else {
    console.error('Falha ao iniciar o servidor: ' + erro.message);
    process.exit(1);
  }
});

servidor.on('listening', () => {
  fs.writeFileSync(path.join(RAIZ, '.preview-port'), String(porta));
  console.log(`Preview em http://localhost:${porta}  (Ctrl+C para parar)`);
});

servidor.listen(porta);
'@
  '.gitignore' = @'
node_modules/
.preview-port
*.log
revisao/diff-pr.txt
'@
  '.github/pull_request_template.md' = @'
## O que foi feito
<!-- Descreva a mudança em 1 a 3 frases. -->

## Por que essa mudança foi necessária
<!-- Problema, tarefa ou issue relacionada (ex.: Closes #12). -->

## Como testar
1. 
2. 
Resultado esperado:

## Checklist do autor (antes de pedir revisão)
- [ ] `npm test` passou localmente
- [ ] `npm run lint` terminou sem erros
- [ ] Incluí ou atualizei testes para o caso principal
- [ ] Não deixei `console.log` nem dados sensíveis no código
- [ ] A mudança é pequena o bastante para ser revisada em uns 15 minutos
'@
  '.github/workflows/ci.yml' = @'
name: Checagens automáticas

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  verificar:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - name: Lint (padrões do time)
        run: npm run lint
      - name: Testes automatizados
        run: npm test
'@
  'docs/CHECKLIST_REVISAO.md' = @'
# Minichecklist de revisão do time

Use antes de dar LGTM ou pedir mudanças (change-request).

- [ ] **A mudança está clara?** A PR tem "o que", "por que" e "como testar"; os commits têm mensagens descritivas.
- [ ] **Há risco de erro?** Entradas vazias, nulas ou inesperadas foram tratadas; nada de dados sensíveis em log.
- [ ] **É possível testar?** Existe teste para o caso principal e as checagens automáticas (lint + testes) passaram.
- [ ] **O comentário está respeitoso?** Fala do código, explica o motivo e sugere um caminho.

Regra de decisão:
- Todos os itens OK, só sugestões pendentes -> **LGTM**.
- Qualquer risco de erro, falta de teste do caso principal ou checagem automática falhando -> **change-request**.
'@
  'docs/ETIQUETA_COMENTARIOS.md' = @'
# Etiqueta de comentários de revisão

Comece cada comentário com um rótulo que diz o peso dele:

| Rótulo | Significado | Bloqueia o merge? |
|---|---|---|
| `bloqueante:` | Problema real que precisa ser corrigido | Sim (change-request) |
| `sugestão:` | Melhoria opcional | Não (pode dar LGTM) |
| `pergunta:` | Dúvida para entender a decisão | Não, até ser respondida |
| `elogio:` | Algo bem feito que vale reconhecer | Não |

## Três regras
1. **Explique o motivo:** diga o que pode dar errado ou o que fica mais difícil de entender.
2. **Sugira melhorias:** proponha um caminho (nome, trecho de código, teste).
3. **Fale do código, não da pessoa:** "esta função..." em vez de "você fez errado...".

## Antes e depois
- Ruim: "Isso está confuso."
- Bom: "sugestão: o nome `chk` não deixa claro que a função valida o token. Pode renomear para `validaToken`?"
'@
  'revisao/REVISAO.md' = @'
# Revisão da PR: feature/validacao-token

Revisor(a):
Data:

## Checklist aplicado (docs/CHECKLIST_REVISAO.md)
- [ ] A mudança está clara?
- [ ] Há risco de erro?
- [ ] É possível testar?
- [ ] Os comentários estão respeitosos?

## Comentários
| # | Arquivo:linha | Rótulo (bloqueante / sugestão / pergunta / elogio) | Comentário |
|---|---|---|---|
| 1 |  |  |  |
| 2 |  |  |  |
| 3 |  |  |  |

## Decisão
- [ ] LGTM (aprovar)
- [ ] Change-request (pedir mudanças)

Justificativa:
'@
  'README.md' = @'
# Laboratório de Code Review

Projeto mínimo usado na aula "Boas práticas de Code Review" (Versionamento de Código).

- `npm test`  - testes automatizados (node:test)
- `npm run lint` - checagem de padrões do time (scripts/lint.js)
- `npm start` - preview local em http://localhost:8080

Branches:
- `main` - versão estável
- `feature/validacao-token` - "PR" a ser revisada pelo grupo
'@
}

# Versão da PR a ser revisada (branch feature/validacao-token) - contém problemas de propósito
$ArquivosBranch = [ordered]@{
  'src/token.js' = @'
/**
 * Utilidades de token de acesso usadas pela tela de login.
 * Formato esperado: prefixo "tk_" + 16 caracteres [a-z0-9] (19 no total).
 */
export const PREFIXO = 'tk_';
export const TAMANHO = 19;

/** Remove espaços extras e padroniza para minúsculas. */
export function normalizaToken(valor) {
  if (typeof valor !== 'string') return '';
  return valor.trim().toLowerCase();
}

/** Oculta o token para exibição: tk_a1b2************ */
export function mascaraToken(valor) {
  const token = normalizaToken(valor);
  if (token.length <= 7) return token;
  return token.slice(0, 7) + '*'.repeat(token.length - 7);
}

// valida
export function chk(t) {
  console.log('token recebido:', t);
  const v = t.trim().toLowerCase();
  const corpo = v.split('_')[1];
  return corpo.length === 16 && v.startsWith(PREFIXO) && v.length == TAMANHO && /^[a-z0-9]+$/.test(corpo);
}
'@
  'app.js' = @'
import { chk, mascaraToken } from './src/token.js';

const campo = document.querySelector('#token');
const botao = document.querySelector('#validar');
const saida = document.querySelector('#resultado');

botao.addEventListener('click', () => {
  if (chk(campo.value)) {
    saida.textContent = 'Token válido: ' + mascaraToken(campo.value);
    saida.className = 'ok';
  } else {
    saida.textContent = 'Token inválido.';
    saida.className = 'erro';
  }
});
'@
}

# ------------------------------------------------------------------ execução
Write-Host ''
Write-Host '=== Laboratório: Boas práticas de Code Review ===' -ForegroundColor White
Write-Host ''

# 1. Git
$Script:Disponivel.git = Executar-Passo 'Verificar Git (recomendado 2.40 ou superior)' {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git não encontrado no PATH.' }
  $v = (Invoke-Nativo 'git' @('--version')).Saida
  if ($v -match '(\d+)\.(\d+)') {
    if ([int]$Matches[1] -lt 2 -or ([int]$Matches[1] -eq 2 -and [int]$Matches[2] -lt 28)) {
      throw "Versão muito antiga ($v). É preciso 2.28 ou superior."
    }
  }
  $v
} 'Instale o Git: no PowerShell rode  winget install --id Git.Git -e  (ou baixe em https://git-scm.com/download/win). Feche e abra o PowerShell e rode o script de novo.'

# 2. Node.js
$Script:Disponivel.node = Executar-Passo 'Verificar Node.js (20 LTS ou superior)' {
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js não encontrado no PATH.' }
  $v = (Invoke-Nativo 'node' @('-v')).Saida
  $maior = [int]($v.TrimStart('v').Split('.')[0])
  if ($maior -lt 20) { throw "Node.js $v é antigo: o executor de testes (node --test) precisa da versão 20 ou superior." }
  "Node.js $v"
} 'Instale o Node.js LTS: winget install --id OpenJS.NodeJS.LTS -e  (ou https://nodejs.org/pt). Feche e abra o PowerShell e rode o script de novo.'

# 3. npm
$Script:Disponivel.npm = Executar-Passo 'Verificar npm' {
  "npm " + (Invoke-Nativo $NpmExe @('-v')).Saida
} 'O npm vem junto com o Node.js. Reinstale o Node.js LTS (winget install --id OpenJS.NodeJS.LTS -e) e reabra o PowerShell.' -Requer node

# 4. VS Code (opcional)
if (Get-Command code -ErrorAction SilentlyContinue) {
  try {
    $vc = ((Invoke-Nativo 'code' @('--version')).Saida -split "`n")[0]
    Registrar 'Verificar VS Code (opcional)' 'OK' "VS Code $vc"
  } catch {
    Registrar 'Verificar VS Code (opcional)' 'AVISO' 'O comando "code" existe, mas não respondeu.' 'Abra o VS Code e use Ctrl+Shift+P > "Shell Command: Install code command in PATH".'
  }
} else {
  Registrar 'Verificar VS Code (opcional)' 'AVISO' 'Comando "code" não encontrado (a atividade funciona com outro editor).' 'Instale com  winget install --id Microsoft.VisualStudioCode -e  ou marque "Adicionar ao PATH" na instalação.'
}

# 5. Pasta do projeto
$Script:Disponivel.pasta = Executar-Passo 'Criar pasta do projeto' {
  if (-not $Destino) {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = $HOME }
    $Destino = Join-Path $docs 'atividade-code-review'
  }
  if ((Test-Path $Destino) -and (Get-ChildItem -Force $Destino | Select-Object -First 1)) {
    $Destino = $Destino + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  }
  New-Item -ItemType Directory -Path $Destino -Force | Out-Null
  $Script:Base = (Resolve-Path $Destino).Path
  $Script:Base
} 'Verifique se você tem permissão de escrita na pasta. Tente outra pasta: -Destino C:\Users\<seu_usuario>\Desktop\lab'

# 6. Arquivos da main
$null = Executar-Passo 'Criar arquivos da versão estável (main)' {
  $n = Escrever-Conjunto $ArquivosMain
  "$n arquivos criados (src, tests, scripts, .github, docs, revisao)"
} 'Verifique permissão de escrita e espaço em disco. Antivírus às vezes bloqueia a pasta Documentos: tente -Destino C:\lab' -Requer pasta

# 7. Repositório Git
$Script:Disponivel.repo = Executar-Passo 'Inicializar repositório Git (branch main)' {
  Push-Location $Script:Base
  try {
    $null = Rodar-Git init
    $null = Rodar-Git symbolic-ref HEAD refs/heads/main
    $nome = (Invoke-Nativo 'git' @('config', 'user.name') -PermitirFalha).Saida
    $email = (Invoke-Nativo 'git' @('config', 'user.email') -PermitirFalha).Saida
    if (-not $nome -or -not $email) {
      $null = Rodar-Git config user.name 'Aluno(a) Lab'
      $null = Rodar-Git config user.email 'aluno@lab.local'
      Registrar 'Identidade do Git' 'AVISO' 'user.name/user.email não configurados: usei "Aluno(a) Lab" só neste repositório.' 'Configure a sua:  git config --global user.name "Seu Nome"  e  git config --global user.email "seu@email"'
    }
    'Repositório criado em ' + $Script:Base
  } finally { Pop-Location }
} 'Confira se o Git está instalado (passo 1). Se a pasta estiver dentro de outro repositório ou do OneDrive, use -Destino C:\lab' -Requer git, pasta

# 8. Commit inicial
$commitOk = Executar-Passo 'Commit inicial na main' {
  Push-Location $Script:Base
  try {
    $null = Rodar-Git add -A
    $null = Rodar-Git commit -q -m 'chore: estrutura inicial do validador de token' -m 'Inclui modelo de PR, workflow de CI, checklist de revisão e etiqueta de comentários.'
    (Rodar-Git log --oneline -1).Saida
  } finally { Pop-Location }
} 'Rode  git status  na pasta do projeto para ver o erro. Em geral é identidade não configurada: git config --global user.name "Seu Nome"' -Requer repo
if (-not $commitOk) { $Script:Disponivel.repo = $false }

# 9. Branch da PR
$Script:Disponivel.branch = Executar-Passo 'Criar branch feature/validacao-token (a PR a revisar)' {
  Push-Location $Script:Base
  try {
    $null = Rodar-Git checkout -q -b feature/validacao-token
    $null = Escrever-Conjunto $ArquivosBranch
    $null = Rodar-Git add -A
    $null = Rodar-Git commit -q -m 'ajustes'
    'Commit "ajustes" criado sem descrição, de propósito (Etapa 1)'
  } finally { Pop-Location }
} 'Rode  git branch -a  e  git status  na pasta do projeto. Apague a pasta e rode o script de novo.' -Requer repo

# 10. Diff da PR
$null = Executar-Passo 'Salvar o diff da PR em revisao\diff-pr.txt' {
  Push-Location $Script:Base
  try {
    $diff = (Rodar-Git diff --no-color main...feature/validacao-token).Saida
    Escrever-Arquivo 'revisao/diff-pr.txt' $diff
    $linhas = ($diff -split "`n").Count
    "$linhas linhas de diff"
  } finally { Pop-Location }
} 'Rode manualmente:  git diff main...feature/validacao-token' -Requer branch

# 11. Testes
$null = Executar-Passo 'Rodar testes automatizados (npm test)' {
  Push-Location $Script:Base
  try {
    $r = Invoke-Nativo $NpmExe @('test')
    $pass = if ($r.Saida -match '# pass (\d+)') { $Matches[1] } else { '?' }
    "$pass testes passaram (repare: nenhum testa a função nova)"
  } finally { Pop-Location }
} 'Veja a saída de  npm test  na pasta do projeto. Precisa do Node.js 20 ou superior.' -Requer npm, pasta

# 12. Lint (falha esperada)
if ($Script:Disponivel.npm -and $Script:Base) {
  Push-Location $Script:Base
  try {
    $r = Invoke-Nativo $NpmExe @('run', 'lint') -PermitirFalha
    if ($r.Codigo -ne 0 -and $r.Saida -match 'console\.log') {
      Registrar 'Rodar checagem de padrões (npm run lint)' 'ESPERADO' 'O lint barrou a PR: 1 erro (console.log) e 1 aviso (nome "chk"). O grupo vai corrigir isso.'
    } elseif ($r.Codigo -eq 0) {
      Registrar 'Rodar checagem de padrões (npm run lint)' 'AVISO' 'O lint passou, mas deveria apontar problemas na branch da PR.' 'Confira se está na branch certa:  git switch feature/validacao-token  e rode  npm run lint'
    } else {
      Registrar 'Rodar checagem de padrões (npm run lint)' 'FALHA' $r.Saida 'Rode  npm run lint  na pasta do projeto e leia a mensagem de erro.'
    }
  } finally { Pop-Location }
} else {
  Registrar 'Rodar checagem de padrões (npm run lint)' 'IGNORADO' 'Depende do npm e da pasta do projeto.' 'Corrija os passos do Node.js/npm e rode o script de novo.'
}

# 13. Servidor de preview
if ($SemServidor) {
  Registrar 'Iniciar servidor de preview' 'IGNORADO' 'Pulado pelo parâmetro -SemServidor.' 'Para iniciar depois:  npm start  (na pasta do projeto)'
} else {
  $null = Executar-Passo 'Iniciar servidor de preview' {
    $arqPorta = Join-Path $Script:Base '.preview-port'
    if (Test-Path $arqPorta) { Remove-Item $arqPorta -Force }
    $env:PORT = [string]$Porta
    $opcoes = @{ FilePath = 'node'; ArgumentList = 'server.cjs'; WorkingDirectory = $Script:Base; PassThru = $true }
    if ($NoWindows) { $opcoes.WindowStyle = 'Minimized' }
    else { $opcoes.RedirectStandardOutput = (Join-Path $Script:Base 'preview.log'); $opcoes.RedirectStandardError = (Join-Path $Script:Base 'preview-erro.log') }
    $proc = Start-Process @opcoes
    $url = $null
    for ($i = 0; $i -lt 20 -and -not $url; $i++) {
      Start-Sleep -Milliseconds 500
      if ($proc.HasExited) { throw 'O servidor encerrou logo após iniciar.' }
      if (Test-Path $arqPorta) {
        $p = (Get-Content $arqPorta -Raw).Trim()
        try {
          $resp = Invoke-WebRequest -Uri "http://localhost:$p/" -UseBasicParsing -TimeoutSec 3
          if ($resp.StatusCode -eq 200) { $url = "http://localhost:$p/" }
        } catch { }
      }
    }
    if (-not $url) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; throw 'O servidor não respondeu em 10 segundos.' }
    $Script:UrlPreview = $url
    $Script:PidPreview = $proc.Id
    "$url  (PID $($proc.Id); para parar: Stop-Process -Id $($proc.Id))"
  } 'Rode na pasta do projeto:  node server.cjs  e leia a mensagem. Se a porta estiver ocupada, use -Porta 8090. Se o Firewall do Windows perguntar, permita acesso em rede privada.' -Requer node, pasta
}

# Abre editor e navegador (só no Windows, sem esperar resposta)
if ($NoWindows -and $Script:Base) {
  if (Get-Command code -ErrorAction SilentlyContinue) { try { Start-Process 'code' -ArgumentList "`"$($Script:Base)`"" -WindowStyle Hidden } catch { } }
  if ($Script:UrlPreview) { try { Start-Process $Script:UrlPreview } catch { } }
}

# ------------------------------------------------------------------ resumo
$ok = @($Script:Resultados | Where-Object { $_.Status -eq 'OK' -or $_.Status -eq 'ESPERADO' }).Count
$falhas = @($Script:Resultados | Where-Object { $_.Status -eq 'FALHA' -or $_.Status -eq 'IGNORADO' })
$avisos = @($Script:Resultados | Where-Object { $_.Status -eq 'AVISO' })

Write-Host ''
Write-Host '=================== RESUMO ===================' -ForegroundColor White
$i = 0
foreach ($r in $Script:Resultados) {
  $i++
  $cor = @{ OK = 'Green'; ESPERADO = 'Cyan'; AVISO = 'Yellow'; FALHA = 'Red'; IGNORADO = 'DarkGray' }[$r.Status]
  Write-Host ('{0,2}. {1,-9} {2}' -f $i, $r.Status, $r.Passo) -ForegroundColor $cor
}
Write-Host ''
Write-Host ("Passos concluídos: {0} de {1}" -f $ok, $Script:Resultados.Count) -ForegroundColor White

if ($falhas.Count -gt 0 -or $avisos.Count -gt 0) {
  Write-Host ''
  Write-Host 'O QUE FALTA CONFIGURAR / COMO CORRIGIR:' -ForegroundColor Yellow
  foreach ($f in @($falhas) + @($avisos)) {
    Write-Host (" - [{0}] {1}" -f $f.Status, $f.Passo) -ForegroundColor Yellow
    if ($f.Detalhe) { Write-Host ("     Motivo: {0}" -f (($f.Detalhe -split "`n")[0])) }
    if ($f.Correcao) { Write-Host ("     Como corrigir: {0}" -f $f.Correcao) }
  }
}

if ($Script:Base) {
  Write-Host ''
  Write-Host 'PRÓXIMOS PASSOS:' -ForegroundColor White
  Write-Host ("  cd `"{0}`"" -f $Script:Base)
  Write-Host '  code .'
  Write-Host '  git log --oneline --graph --all'
  if ($Script:UrlPreview) { Write-Host ("  Preview: {0}" -f $Script:UrlPreview) }
}
Write-Host ''

if ($falhas.Count -gt 0) { exit 1 } else { exit 0 }
