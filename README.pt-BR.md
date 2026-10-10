<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img alt="updatool" src="assets/logo-light.svg" width="420">
  </picture>
</p>

<p align="center">
  <b>Build rápido. Publicação sem queda. IAs fazendo deploy com segurança.</b><br>
  Ferramenta e metodologia de deploy, para qualquer linguagem, em um servidor ou poucos —<br>
  slots blue/green, build incremental, trava de deploy de verdade e saída que humanos <i>e</i> IAs entendem.
</p>

<p align="center"><a href="README.md">English</a> · <a href="docs/METHODOLOGY.md">A metodologia</a> · <a href="skills/updatool/SKILL.md">Skill para IAs</a></p>

---

## Por que existe

Quem hospeda o próprio sistema costuma cair em um de dois extremos:

- **`docker compose up -d`**: simples, mas cada deploy reinicia o app e os usuários veem erro por 5 a 30 segundos.
- **Uma plataforma** (Kubernetes, um painel PaaS): sem queda, mas é maquinário demais para um ou dois servidores.

E aparecem as dores do dia a dia:

| Dor | O que o updatool faz |
|---|---|
| Mudar uma linha refaz o build inteiro (minutos) | Builder persistente + receitas de cache por linguagem → **segundos** |
| Testes e checagem de tipos rodam *dentro* do build, toda vez | Uma **etapa de checagem** (`CHECK_CMD`) roda antes; o build fica incremental |
| Deploy = reinício = erro para o usuário | **Dois slots fixos** (blue/green): saúde primeiro, uma troca atômica, drenagem |
| Voltar atrás exige rebuildar a versão anterior | O slot anterior **fica parado, pronto** → `updatool rollback` em segundos |
| Duas pessoas (ou duas IAs) publicam juntas e uma sobrescreve a outra | **Trava pelo kernel** (`flock`) + proteção `--expect <versão>` |
| O build no servidor de produção deixa o app lento | Builder com **limite de CPU e memória** |
| Você já usa Traefik / Caddy / Nginx | O updatool **escreve a rota** para o proxy que você já tem |
| IAs não leem logs de humanos com confiabilidade | **`--json` em todo comando** + códigos de saída estáveis |

## Como funciona

A produção só é tocada em **um** passo, a troca de rota, e só depois que a versão nova respondeu à checagem de saúde. Se algo falhar antes disso, ninguém percebe. Se a checagem pública falhar depois, o updatool volta sozinho.

## Começo rápido

```bash
curl -fsSL https://raw.githubusercontent.com/joaoventuri/updatool/main/install.sh | sh
updatool init      # detecta a linguagem e cria o updatool.conf (+ Dockerfile com cache)
updatool doctor    # confere docker, buildx, rede, proxy e cache
updatool ship      # checagem → build → blue/green → pronto
```

## Números reais

Medido num app Next.js 16 em produção (VM de 4 vCPU dividida com o app no ar):

| | Antes | Com o método |
|---|---|---|
| Build com mudança de uma linha | ~236 s | **~40 s** |
| Troca de versão | ~150 s | **~20–30 s** |
| Requisições com falha em 6 trocas seguidas, sob carga | — | **0 de 2.504** |
| Voltar atrás | rebuild (~7 min) | **segundos** |

## Feito para IAs

Vem com uma **[skill](skills/updatool/SKILL.md)** no formato aberto `SKILL.md`, lido por Claude Code, Codex, Cursor, Gemini CLI e outros. Ela ensina a IA a publicar como um engenheiro cuidadoso:
- olhar o estado antes;
- proteger contra corrida (`--expect`);
- nunca quebrar a trava de outra pessoa;
- voltar atrás rápido.

Comandos, configuração e comparação com Kamal, Coolify e Dokploy: [README em inglês](README.md). A metodologia completa: [docs/METHODOLOGY.md](docs/METHODOLOGY.md).

Licença [MIT](LICENSE).
