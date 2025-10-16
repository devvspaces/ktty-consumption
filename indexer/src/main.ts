import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AppModule } from './app.module';
import { BullBoardService } from './dashboard/bull-board.service';

async function bootstrap() {
  const logger = new Logger('Bootstrap');

  try {
    const app = await NestFactory.create(AppModule, {
      logger: ['log', 'error', 'warn', 'debug', 'verbose'],
    });

    // Get configuration service
    const configService = app.get(ConfigService);
    const port = configService.get<number>('app.port');
    const environment = configService.get<string>('app.environment');

    // Enable CORS - allow all origins
    app.enableCors({
      origin: true,
      credentials: true,
    });

    // Enable validation
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );

    // Setup Bull Dashboard
    const bullBoardService = app.get(BullBoardService);
    app.use('/admin/queues', bullBoardService.getRouter());

    // Enable graceful shutdown
    app.enableShutdownHooks();

    // Setup graceful shutdown handling
    const gracefulShutdownTimeoutMs = configService.get<number>('app.gracefulShutdownTimeoutMs');
    
    process.on('SIGTERM', async () => {
      logger.log('SIGTERM received, starting graceful shutdown...');
      setTimeout(() => {
        logger.error('Forced shutdown due to timeout');
        process.exit(1);
      }, gracefulShutdownTimeoutMs);
      
      await app.close();
      process.exit(0);
    });

    process.on('SIGINT', async () => {
      logger.log('SIGINT received, starting graceful shutdown...');
      setTimeout(() => {
        logger.error('Forced shutdown due to timeout');
        process.exit(1);
      }, gracefulShutdownTimeoutMs);
      
      await app.close();
      process.exit(0);
    });

    // Handle uncaught exceptions
    process.on('uncaughtException', (error) => {
      logger.error('Uncaught Exception:', error);
      process.exit(1);
    });

    process.on('unhandledRejection', (reason, promise) => {
      logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
      process.exit(1);
    });

    await app.listen(port);
    
    logger.log(`🚀 KTTY Companions Indexer is running`);
    logger.log(`📡 Environment: ${environment}`);
    logger.log(`🌐 Server: http://localhost:${port}`);
    logger.log(`🏥 Health: http://localhost:${port}/health`);
    logger.log(`📊 Status: http://localhost:${port}/indexer/status`);
    logger.log(`📋 Queue Dashboard: http://localhost:${port}/admin/queues`);
    logger.log(`⚡ Ready to index Transfer and MetadataUpdated events!`);

  } catch (error) {
    logger.error('Failed to start application:', error);
    process.exit(1);
  }
}

bootstrap();