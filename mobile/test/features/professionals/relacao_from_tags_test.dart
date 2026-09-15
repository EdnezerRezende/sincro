import 'package:flutter_test/flutter_test.dart';
import 'package:sincro_mobile/features/professionals/relacao_from_tags.dart';

void main() {
  test('maps tags to the trusted-contact relation', () {
    expect(relacaoFromTags(['Psicólogo', 'Adultos']), 'PSICOLOGO');
    expect(relacaoFromTags(['psiquiatra']), 'PSIQUIATRA');
    expect(relacaoFromTags(['T.O.']), 'T.O.');
    expect(relacaoFromTags(['Terapeuta Ocupacional']), 'T.O.');
    expect(relacaoFromTags(['Neuroafirmativo']), 'OUTRO');
    expect(relacaoFromTags([]), 'OUTRO');
  });

  test('validates the professional phone for a trusted contact', () {
    expect(telefoneValidoParaContato('+5511999990000'), isTrue);
    expect(telefoneValidoParaContato('+55 (11) 99999-0000'), isTrue);
    expect(telefoneValidoParaContato('11999990000'), isFalse);
  });
}
