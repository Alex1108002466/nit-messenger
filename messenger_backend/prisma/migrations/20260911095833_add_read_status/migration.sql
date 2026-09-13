-- AlterTable
ALTER TABLE "Chat" ADD COLUMN     "participantOneLastReadAt" TIMESTAMP(3),
ADD COLUMN     "participantTwoLastReadAt" TIMESTAMP(3);
