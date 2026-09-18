import 'package:dio/dio.dart';
import 'email_body.dart';
import 'email_summary.dart';

/// Uma página de resumos de e-mail. `proximoCursor` é `null` quando não há mais páginas —
/// a tela usa isso para decidir se mostra "Carregar mais".
class PaginaResumos {
  const PaginaResumos({required this.itens, this.proximoCursor});

  final List<EmailSummary> itens;
  final String? proximoCursor;
}

class EmailSummaryRepository {
  EmailSummaryRepository(this._dio);

  final Dio _dio;

  /// Busca uma página de resumos. Sem `cursor`, começa do mais recente; o backend mantém
  /// compatibilidade com o formato antigo (array puro) quando nenhum parâmetro de paginação é
  /// enviado, mas este método sempre manda `limite` e por isso sempre recebe `{itens, proximoCursor}`.
  Future<PaginaResumos> listar({String? cursor, int limite = 50}) async {
    final response = await _dio.get('/resumos-email', queryParameters: {
      'limite': '$limite',
      if (cursor != null) 'cursor': cursor,
    });
    final body = response.data;
    // Um app já distribuído pode falar com um backend ainda não atualizado com o deploy mais
    // recente (`./deploy.sh` não é atômico com a publicação da build mobile) — nesse cenário o
    // backend antigo devolve o array puro de antes da paginação existir. Tratamos isso como uma
    // única página completa (sem próximo cursor) em vez de deixar o cast abaixo estourar um
    // TypeError opaco para quem chamou.
    if (body is List) {
      return PaginaResumos(
        itens: body
            .map((json) => EmailSummary.fromJson(json as Map<String, dynamic>))
            .toList(),
        proximoCursor: null,
      );
    }
    final data = body as Map<String, dynamic>;
    final itens = data['itens'];
    if (itens is! List) {
      throw FormatException(
        'Resposta inesperada de GET /resumos-email: campo "itens" ausente ou não é uma lista '
        '(recebido: ${itens.runtimeType}).',
      );
    }
    final proximoCursor = data['proximoCursor'];
    return PaginaResumos(
      itens: itens.map((json) => EmailSummary.fromJson(json as Map<String, dynamic>)).toList(),
      // Se o backend mandar algo que não seja String (ex.: número por bug de serialização),
      // tratamos como se não houvesse próxima página em vez de propagar um cast inválido —
      // a pior consequência é esconder uma página real, nunca travar a lista.
      proximoCursor: proximoCursor is String ? proximoCursor : null,
    );
  }

  /// Mantido para compatibilidade com chamadores/telas que só precisam da primeira página;
  /// devolve só os itens, descartando o cursor de paginação.
  Future<List<EmailSummary>> list() async => (await listar()).itens;

  /// Pede ao backend para sincronizar a caixa agora, fora do ciclo do cron. Qualquer 2xx é sucesso
  /// (inclusive 202, que o backend usa tanto para "sincronização recente demais, ignorada" quanto
  /// para "já há uma sincronização em andamento"); 403 (Gmail não conectado) e outros erros
  /// propagam como [DioException] — a tela decide o que mostrar.
  Future<void> sincronizar() async {
    await _dio.post(
      '/resumos-email/sincronizar',
      // O receiveTimeout global do ApiClient é 30s, pensado para chamadas pontuais a um LLM. A
      // primeira sincronização de uma conta pode varrer ~200 mensagens e classificar cada uma —
      // facilmente ultrapassa isso. Damos mais fôlego só aqui, sem mexer no timeout global (que
      // continua correto para as outras chamadas deste repositório).
      options: Options(receiveTimeout: const Duration(seconds: 120)),
    );
  }

  /// Full body for READING the e-mail — never touches an LLM, so it can't fail because a
  /// third-party AI provider is down. Fetched fresh on every open rather than cached alongside
  /// [EmailSummary]: the backend already fetches it live from Gmail on demand (see
  /// `GET /resumos-email/:id/conteudo`), so there's nothing here worth persisting client-side.
  /// The backend converts HTML-only e-mails to readable text; [EmailBody.ehPreview] is only `true`
  /// on the rare case where it couldn't even do that and fell back to Gmail's short snippet.
  Future<EmailBody> conteudo(String emailId) async {
    final response = await _dio.get('/resumos-email/$emailId/conteudo');
    return EmailBody.fromJson(response.data as Map<String, dynamic>);
  }

  /// Tira o e-mail da caixa de entrada no Gmail de verdade (remove só o label INBOX — reversível
  /// pelo próprio Gmail) e apaga a linha local no mesmo request; o backend nunca detectaria essa
  /// remoção sozinho depois (o sync incremental só reage a mensagens novas). Lança [DioException]
  /// com status 403 quando a conta ainda não concedeu o escopo `gmail.modify` — a tela trata isso
  /// mostrando o caminho de reconexão, nunca falhando em silêncio.
  Future<void> arquivar(String emailId) async {
    await _dio.post('/resumos-email/$emailId/arquivar');
  }

  /// Move o e-mail para a lixeira do Gmail (recuperável por lá por ~30 dias — nunca uma exclusão
  /// permanente) e apaga a linha local no mesmo request. Mesmo tratamento de escopo ausente que
  /// [arquivar].
  Future<void> excluir(String emailId) async {
    await _dio.post('/resumos-email/$emailId/excluir');
  }
}
