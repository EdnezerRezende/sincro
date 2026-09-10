/// Corpo completo de um e-mail (`GET /resumos-email/:id/conteudo`).
///
/// [ehPreview] é `true` quando o backend não conseguiu montar um texto legível a partir do e-mail
/// (nem `text/plain`, nem `text/html`) e caiu de volta para o `snippet` do Gmail — um resumo de
/// ~200 caracteres, não a mensagem inteira. A tela precisa deixar isso claro em vez de mostrar o
/// trecho como se fosse o e-mail completo.
class EmailBody {
  const EmailBody({required this.corpo, required this.ehPreview});

  final String corpo;
  final bool ehPreview;

  factory EmailBody.fromJson(Map<String, dynamic> json) {
    return EmailBody(
      corpo: json['corpo'] as String? ?? '',
      ehPreview: json['ehPreview'] as bool? ?? false,
    );
  }
}
