-- AlterTable
ALTER TABLE "conexoes_gmail" ADD COLUMN     "tem_escopo_agenda" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "tem_escopo_envio" BOOLEAN NOT NULL DEFAULT false;
