/// Intervalo mínimo entre revalidações disparadas por `AppLifecycleState.resumed`. 30 s é curto
/// o bastante para o usuário nunca perceber dados desatualizados ao voltar ao app e longo o
/// bastante para não gerar rajada de requisições em quem alterna de app repetidamente.
const Duration kRevalidationMinInterval = Duration(seconds: 30);
