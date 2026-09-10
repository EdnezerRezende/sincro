import 'package:dio/dio.dart';
import 'email_body.dart';
import 'email_summary.dart';

class EmailSummaryRepository {
  EmailSummaryRepository(this._dio);

  final Dio _dio;

  Future<List<EmailSummary>> list() async {
    final response = await _dio.get('/resumos-email');
    final data = response.data as List<dynamic>;
    return data.map((json) => EmailSummary.fromJson(json as Map<String, dynamic>)).toList();
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
