import { Module } from '@nestjs/common';
import { ConfigModule as NestConfigModule } from '@nestjs/config';
import configuration from './configuration';
import { ConfigValidationService } from './config-validation.service';

@Module({
  imports: [
    NestConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
      envFilePath: ['.env.local', '.env'],
      expandVariables: true,
    }),
  ],
  providers: [ConfigValidationService],
  exports: [ConfigValidationService],
})
export class ConfigModule {}