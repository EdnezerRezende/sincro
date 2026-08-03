export interface EmailToClassify {
  remetente: string;
  assunto: string;
  corpo: string;
}

export interface EmailClassificationContext {
  tomPreferido?: string;
}

export interface EmailClassification {
  categoria: 'PRECISA_ATENCAO' | 'PODE_ESPERAR';
  resumoCurto: string;
}

export interface EmailClassifier {
  classify(email: EmailToClassify, context: EmailClassificationContext): Promise<EmailClassification>;
}
