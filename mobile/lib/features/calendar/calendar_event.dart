/// Categoria visual do evento, exibida como ícone na lista do dia. Espelha
/// `CategoriaEvento` em `backend/src/calendar/calendar-api-client.service.ts`.
/// `financeiro` só é considerado "gerado por Finanças" (ver [CalendarEvent.isGeradoPorFinancas])
/// quando também vem acompanhado de [CalendarEvent.lancamentoId] — o backend nunca envia um
/// sem o outro, mas o parse trata os dois campos de forma independente por segurança.
enum CategoriaEvento { financeiro, social, trabalho, geral }

CategoriaEvento categoriaEventoFromJson(String? value) {
  switch (value) {
    case 'FINANCEIRO':
      return CategoriaEvento.financeiro;
    case 'SOCIAL':
      return CategoriaEvento.social;
    case 'TRABALHO':
      return CategoriaEvento.trabalho;
    default:
      return CategoriaEvento.geral;
  }
}

String categoriaEventoToJson(CategoriaEvento categoria) {
  switch (categoria) {
    case CategoriaEvento.financeiro:
      return 'FINANCEIRO';
    case CategoriaEvento.social:
      return 'SOCIAL';
    case CategoriaEvento.trabalho:
      return 'TRABALHO';
    case CategoriaEvento.geral:
      return 'GERAL';
  }
}

/// Model para um evento de calendário sincronizado do Google Calendar.
///
/// Os nomes dos campos espelham exatamente o JSON devolvido/aceito pelo backend
/// (`EventoCalendario` em `backend/src/calendar/calendar-api-client.service.ts` e o
/// `CriarEventoDto` em `backend/src/calendar/dto/criar-evento.dto.ts`) — em português, para não
/// precisar de nenhuma tradução de campo entre o app e a API.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.dataHoraInicio,
    required this.dataHoraFim,
    this.ehDiaInteiro = false,
    this.categoria = CategoriaEvento.geral,
    this.lancamentoId,
  });

  final String id;
  final String titulo;
  final String descricao;
  final DateTime dataHoraInicio;
  final DateTime dataHoraFim;
  final bool ehDiaInteiro; // true se o evento é um evento de dia inteiro (all-day)
  final CategoriaEvento categoria;
  final String? lancamentoId; // presente só quando categoria == financeiro

  /// True quando o evento foi criado pelo fluxo de sincronização de Finanças (categoria
  /// financeiro + link para o lançamento de origem) — nesse caso a Agenda mostra o evento
  /// como somente leitura, já que Finanças é a fonte da verdade.
  bool get isGeradoPorFinancas =>
      categoria == CategoriaEvento.financeiro && lancamentoId != null;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String? ?? '',
      titulo: json['titulo'] as String? ?? 'Evento sem título',
      descricao: json['descricao'] as String? ?? '',
      // `.toLocal()` é essencial aqui: quando a string ISO trazida pelo backend tem offset (ou
      // "Z"), `DateTime.parse` devolve um DateTime com `isUtc == true` — ler `.hour`/`.day` direto
      // dele exibe o horário em UTC, não no fuso do usuário. Um evento às 15h em São Paulo
      // (-03:00) viraria "18:00" na tela. Convertendo para local uma única vez aqui, todo o resto
      // do app (formatação de hora, agrupamento por dia no grid do mês) já recebe o instante certo.
      dataHoraInicio: DateTime.parse(json['dataHoraInicio'] as String? ?? '2000-01-01').toLocal(),
      dataHoraFim: DateTime.parse(json['dataHoraFim'] as String? ?? '2000-01-01').toLocal(),
      ehDiaInteiro: json['ehDiaInteiro'] as bool? ?? false,
      categoria: categoriaEventoFromJson(json['categoria'] as String?),
      lancamentoId: json['lancamentoId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'titulo': titulo,
    'descricao': descricao,
    'dataHoraInicio': dataHoraInicio.toIso8601String(),
    'dataHoraFim': dataHoraFim.toIso8601String(),
    'ehDiaInteiro': ehDiaInteiro,
    'categoria': categoriaEventoToJson(categoria),
    if (lancamentoId != null) 'lancamentoId': lancamentoId,
  };
}
