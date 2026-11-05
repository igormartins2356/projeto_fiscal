# Emissão de NF-e/NFC-e direto com a SEFAZ — mapa de referência

> **Status: nada disso está implementado.** O produto hoje **valida XML já autorizado** que o
> contador apresenta (`ARQUITETURA.md` §11). Este documento é o mapa do que uma emissão exigiria, e
> onde cada informação está na documentação oficial espelhada em `api/storage/sefaz` — para que a
> decisão de construir, se vier, comece de um levantamento feito e não de uma página em branco.
>
> Fonte: MOC 7.0 (150 páginas), Anexo I seções 3.3, 4.1 e 4.3, Anexos II a IV, e o manual de
> especificações técnicas do DANFE NFC-e. Levantado em 12/09/2026.

---

## 1. O que o projeto já tem, e o que falta

Existe hoje só a **leitura passiva** do resultado da emissão: o parser lê o protocolo de autorização
(`protNFe/infProt`), a inutilização e os eventos do XML, e projeta o cancelamento no status do
documento. Nenhuma assinatura, nenhum certificado, nenhuma chamada de webservice, e nenhuma
dependência para isso no `Gemfile`.

O único certificado já decidido é um e-CNPJ A1 **para ler** a API de tabelas da SVRS
(`DATA_SOURCES.md` §4), não para assinar documento fiscal.

Para emitir, seria preciso acrescentar, em ordem de dependência: leitura de certificado A1 ou A3,
assinatura XML no padrão exigido, cliente dos webservices, controle de numeração e série, montagem do
DANFE, e o fluxo de contingência.

---

## 2. Certificado digital

Emitido por Autoridade Certificadora credenciada na **ICP-Brasil**, tipo **A1** (arquivo) ou **A3**
(cartão ou token), e precisa conter:

| Titular | Campo do certificado |
|---|---|
| Pessoa jurídica | CNPJ em `OtherName` OID **2.16.76.1.3.3** |
| Pessoa física | CPF em `OtherName` OID **2.16.76.1.3.1** |

O certificado é exigido em **dois momentos distintos**, e isso tem consequência prática: são duas
validações separadas, com códigos de rejeição próprios.

1. **Transmissão**, no protocolo TLS. Valida o certificado do transmissor.
2. **Assinatura** do documento. Valida o certificado de assinatura, que precisa ter o CNPJ base do
   emitente da nota.

A diferença entre A1 e A3 decide a arquitetura: A1 é arquivo e pode ficar num cofre de segredos, com
assinatura no servidor; A3 exige o dispositivo físico presente, o que empurra a assinatura para a
máquina do cliente ou para um serviço dedicado. Essa é a primeira decisão de projeto, e ela muda
tudo o que vem depois.

## 3. Assinatura digital

O XML é assinado com certificado que contenha o CNPJ de um dos estabelecimentos da empresa emissora.

O manual é explícito sobre o que **não** deve constar no XML, porque a SEFAZ obtém do próprio
certificado, e mandar assim mesmo gera rejeição:

```
<X509SubjectName>   <X509IssuerSerial>   <X509IssuerName>
<X509SerialNumber>  <X509SKI>
```

E orienta evitar `<KeyValue>`, pela mesma razão.

Validações da assinatura, com os códigos que o contribuinte recebe (grupo F do Anexo I, já no
catálogo `sefaz_rejeicao`):

| Código | Rejeição |
|---|---|
| 298 | Assinatura difere do padrão do Sistema |
| 297 | Assinatura difere do calculado |
| 213 | CNPJ-Base do Emitente difere do CNPJ-Base do Certificado |

## 4. Chave de acesso e seu dígito verificador

A chave tem 43 dígitos mais 1 de verificação. O dígito sai de **módulo 11 com pesos de 2 a 9**,
aplicados da direita para a esquerda: multiplica cada dígito pelo seu peso, soma, divide por 11, e o
dígito é `11 menos o resto`. O manual traz o cálculo passo a passo em 2.2.6.2, com exemplo numérico
conferível.

Duas regras de validação dependem disso, e são das primeiras que uma emissão precisa acertar: o campo
`Id` tem de corresponder à concatenação dos campos (rejeição **502**) e a chave tem de ter o dígito
correto. Vale notar que **não temos nenhuma regra sobre chave de acesso hoje**, e a SEFAZ tem 57
(ver `docs/tasks/analise-documentacao-sefaz/REJEICOES.md`).

## 5. Os webservices

Oito serviços, todos citados no MOC 7.0 capítulo 5, cada um com leiaute de entrada, de retorno e
regras próprias:

| Serviço | Função |
|---|---|
| `NfeAutorizacao` | envia o lote de notas para autorização |
| `NfeRetAutorizacao` | busca o resultado do lote, pelo número do recibo |
| `NfeConsultaProtocolo` | consulta a situação de uma nota pela chave |
| `NfeStatusServico` | verifica se o serviço da UF está no ar |
| `NfeInutilizacao` | inutiliza faixa de numeração não usada |
| `NFeRecepcaoEvento` | registra evento (cancelamento, carta de correção, manifestação) |
| `NfeConsultaCadastro` | consulta a situação cadastral do contribuinte |
| `NfeDistribuicaoDFe` | baixa documentos e eventos de interesse do destinatário |

O último é o mais interessante para o produto **como ele é hoje**: `NfeDistribuicaoDFe` é o caminho
para buscar automaticamente as notas emitidas contra o cliente, em vez de depender do contador subir
XML à mão. Isso é valor de validador, não de emissor, e pode ser feito antes e independente.

## 6. Modelo operacional

**Síncrono e assíncrono.** O envio de lote pode responder na hora ou devolver um **recibo**, que
depois é consultado no `NfeRetAutorizacao` até sair o **protocolo**. Quem implementa precisa tratar os
dois, porque a escolha é da UF.

**Ambientes.** Homologação e produção são separados, e o campo `tpAmb` do XML diz qual. Nosso
importador já descarta documento de homologação na ingestão, com motivo registrado.

**Uso indevido.** A seção 4.3 do Anexo I define limites de consumo dos webservices, com 6 regras e
códigos próprios (por exemplo **656**, consumo indevido pelo aplicativo da empresa, disparado após 30
rejeições iguais). Quem emite precisa respeitar isso, senão é bloqueado.

## 7. Contingência

Modalidades citadas no manual, cada uma com sua documentação:

| Modalidade | Quando | Onde está documentado |
|---|---|---|
| **EPEC** | Evento prévio de emissão em contingência, código de evento 110140 | MOC 7.0 §3.3, com 17 subseções |
| **SVC-AN / SVC-RS** | SEFAZ Virtual de Contingência, quando a autorizadora está fora | MOC 7.0 §3.3.17 |
| **Off-line NFC-e** | NFC-e emitida sem conexão, transmitida depois | Manual de especificações técnicas da Contingência Off-line |
| **FS-DA** | Formulário de segurança | Anexo III (NF-e) e Anexo IV (NFC-e) |

## 8. Eventos

Os códigos que o emissor registra pelo `NFeRecepcaoEvento`:

| Código | Evento |
|---|---|
| 110110 | Carta de correção eletrônica |
| 110111 | Cancelamento pelo emitente |
| 110112 | Cancelamento por substituição (prazo não superior a 168 horas) |
| 110140 | EPEC, emissão em contingência |
| 110150 | Ator interessado na NF-e, transportador |
| 210200 a 210240 | Manifestação do destinatário: confirmação, ciência, desconhecimento, operação não realizada |

Hoje o parser **lê** esses eventos do XML e projeta o cancelamento. A carta de correção e a
manifestação estão marcadas como pendentes no canônico: são lidas mas não se projetam no status.

## 9. QR Code da NFC-e

Duas versões coexistem, e a diferença é grande:

- **Versão 100**: parâmetros concatenados com `&`, incluindo chave, ambiente, destinatário, data,
  valor, valor do ICMS, digest da assinatura, identificador do token e o hash.
- **Versão 2**: formato compacto, com os campos separados por `|`, na ordem chave de acesso, versão,
  tipo de ambiente, identificador do CSC e código hash.

Dois detalhes que quebram a emissão se ignorados: o conteúdo precisa ir dentro de `<![CDATA[...]]>`,
porque `&` é caractere reservado no XML; e o uso de maiúsculas e minúsculas tem de seguir o manual
exatamente. Os endereços de consulta variam **por UF**, e estão no manual de padrões técnicos do
DANFE NFC-e e no Anexo I (a tabela de URLs por UF).

O **CSC** (Código de Segurança do Contribuinte) é fornecido pela SEFAZ da UF e entra no cálculo do
hash. Sem ele não há NFC-e.

## 10. Responsável técnico

O grupo `infRespTec` identifica quem desenvolveu o software emissor, e em alguns casos exige o
**CSRT** (Código de Segurança do Responsável Técnico), com o `hashCSRT` calculado a partir dele. O
MOC 7.0 §2.2.10 traz o procedimento e um exemplo conferível. O parser já lê esse grupo do XML.

## 11. As 38 validações de infraestrutura

A seção 4.1 do Anexo I traz, em cinco grupos, o que a SEFAZ verifica antes de olhar o conteúdo
fiscal. Todas já estão no catálogo `sefaz_rejeicao`, classificadas como infraestrutura, e servem de
checklist para quem for implementar a emissão:

| Grupo | Verifica | Regras |
|---|---|---|
| A | Certificado de transmissão, no TLS | 7 |
| B | Mensagem no webservice: tamanho, XML bem formado, serviço no ar | 6 |
| D | Área de dados: schema, tag raiz, atributo de versão, namespace, caracteres de edição | 15 |
| E | Certificado digital de assinatura | 7 |
| F | A assinatura em si | 3 |

Os códigos são: 108, 109, 213, 214, 215, 225, 239, 243, 280 a 286, 290 a 298, 402, 404, 410, 491 a
493, 516, 517, 565, 568, 587, 588, 764 e 776.

---

## 12. Onde buscar cada coisa

| Assunto | Documento | Seção |
|---|---|---|
| Leiaute do XML | Esquemas XML (pacote de liberação) e Anexo I | seção 2 |
| Regra de validação e código de rejeição | Anexo I | seção 4 |
| Certificado e assinatura | MOC 7.0 | §4.2.3 e §4.2.4 |
| Chave de acesso e dígito verificador | MOC 7.0 | §2.2.6 |
| Webservices, leiaute e fluxo | MOC 7.0 | capítulo 5 |
| Síncrono, assíncrono, recibo, protocolo, ambientes | MOC 7.0 | §4.3 |
| Eventos e manifestação | MOC 7.0 | capítulo 3 |
| EPEC e SEFAZ Virtual de Contingência | MOC 7.0 | §3.3 |
| Contingência com formulário de segurança | Anexos III e IV | — |
| DANFE e código de barras | Anexo II | — |
| DANFE NFC-e e QR Code | Manual de especificações técnicas do DANFE NFC-e | — |
| Contingência off-line da NFC-e | Manual de especificações técnicas da Contingência Off-line | — |
| Responsável técnico e CSRT | MOC 7.0 | §2.2.10 |
| Limite de consumo dos webservices | Anexo I | §4.3 |

Tudo espelhado em `api/storage/sefaz`, com procedência em `api/db/data/sefaz/manifest.json`. O texto
extraído dos manuais fica em `api/storage/sefaz/texto`, fora do git.

## 13. Se a decisão for construir

A ordem que a documentação sugere, do mais independente ao mais acoplado:

1. **`NfeDistribuicaoDFe` primeiro.** Não exige assinar nada além da própria consulta, e entrega
   valor ao validador que já existe: buscar as notas emitidas contra o cliente em vez de esperar o
   upload. É o único item desta lista que vale a pena mesmo sem emissor.
2. **Decidir A1 ou A3**, porque isso define onde a assinatura acontece.
3. **Assinatura e `NfeStatusServico`**, que é o serviço mais simples e prova a comunicação ponta a
   ponta com certificado.
4. **`NfeAutorizacao` em homologação**, tratando os dois fluxos, síncrono e assíncrono.
5. **Numeração, série e inutilização**, que são controle de estado e não de comunicação.
6. **DANFE e QR Code.**
7. **Contingência**, por último, porque depende de todo o resto funcionar.

Nada disso está planejado. Virar projeto exige decisão de produto, e o plano em
`docs/tasks/analise-documentacao-sefaz/PLANO.md` registra a emissão como documentação, não como
implementação.
