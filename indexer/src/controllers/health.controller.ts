import { Controller, Get, Logger } from '@nestjs/common';
import {
  HealthCheckService,
  HealthCheck,
  HealthCheckResult,
  HealthIndicatorResult,
} from '@nestjs/terminus';
import { DatabaseService } from '../database/database.service';
import { SyncService } from '../services/sync.service';
import { EventListenerService } from '../services/event-listener.service';

@Controller('health')
export class HealthController {
  private readonly logger = new Logger(HealthController.name);

  constructor(
    private health: HealthCheckService,
    private databaseService: DatabaseService,
    private syncService: SyncService,
    private eventListener: EventListenerService,
  ) {}

  @Get()
  @HealthCheck()
  async check(): Promise<HealthCheckResult> {
    return this.health.check([
      () => this.databaseHealthCheck(),
      () => this.syncHealthCheck(),
      () => this.eventListenerHealthCheck(),
    ]);
  }

  @Get('ready')
  async ready(): Promise<{ status: string; timestamp: string; ready: boolean }> {
    try {
      // Check if all critical services are ready
      const [dbHealthy, syncStatus, eventStatus] = await Promise.all([
        this.databaseService.isHealthy(),
        this.syncService.getSyncStatus(),
        Promise.resolve(this.eventListener.getStatus()),
      ]);

      const isReady = dbHealthy && 
                     syncStatus.isHealthy && 
                     eventStatus.isListening &&
                     syncStatus.blocksBehind <= 50; // Allow some blocks behind for readiness

      return {
        status: isReady ? 'ready' : 'not ready',
        timestamp: new Date().toISOString(),
        ready: isReady,
      };
    } catch (error) {
      this.logger.error('Readiness check failed:', error);
      return {
        status: 'not ready',
        timestamp: new Date().toISOString(),
        ready: false,
      };
    }
  }

  @Get('live')
  async live(): Promise<{ status: string; timestamp: string; alive: boolean }> {
    try {
      // Basic liveness check - just verify the service is responding
      const dbHealthy = await this.databaseService.isHealthy();
      
      return {
        status: dbHealthy ? 'alive' : 'unhealthy',
        timestamp: new Date().toISOString(),
        alive: dbHealthy,
      };
    } catch (error) {
      this.logger.error('Liveness check failed:', error);
      return {
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        alive: false,
      };
    }
  }

  private async databaseHealthCheck(): Promise<HealthIndicatorResult> {
    const key = 'database';
    
    try {
      const isHealthy = await this.databaseService.isHealthy();
      
      if (isHealthy) {
        return {
          [key]: {
            status: 'up',
            message: 'Database connection is healthy',
          },
        };
      } else {
        return {
          [key]: {
            status: 'down',
            message: 'Database connection failed',
          },
        };
      }
    } catch (error) {
      return {
        [key]: {
          status: 'down',
          message: error.message || 'Database health check failed',
        },
      };
    }
  }

  private async syncHealthCheck(): Promise<HealthIndicatorResult> {
    const key = 'sync';
    
    try {
      const status = await this.syncService.getSyncStatus();
      
      const isHealthy = status.isHealthy && status.blocksBehind <= 20;
      
      if (isHealthy) {
        return {
          [key]: {
            status: 'up',
            message: `Sync healthy, ${status.blocksBehind} blocks behind`,
            details: {
              currentBlock: status.currentBlock,
              lastProcessedBlock: status.lastProcessedBlock,
              blocksBehind: status.blocksBehind,
              isSyncing: status.isSyncing,
            },
          },
        };
      } else {
        return {
          [key]: {
            status: 'down',
            message: status.errorMessage || `Sync unhealthy, ${status.blocksBehind} blocks behind`,
            details: {
              currentBlock: status.currentBlock,
              lastProcessedBlock: status.lastProcessedBlock,
              blocksBehind: status.blocksBehind,
              isSyncing: status.isSyncing,
              errorMessage: status.errorMessage,
            },
          },
        };
      }
    } catch (error) {
      return {
        [key]: {
          status: 'down',
          message: error.message || 'Sync health check failed',
        },
      };
    }
  }

  private async eventListenerHealthCheck(): Promise<HealthIndicatorResult> {
    const key = 'eventListener';
    
    try {
      const status = this.eventListener.getStatus();
      
      const isHealthy = status.isListening && status.reconnectAttempts < 5;
      
      if (isHealthy) {
        return {
          [key]: {
            status: 'up',
            message: `Event listener active on ${status.currentProvider}`,
            details: {
              isListening: status.isListening,
              currentProvider: status.currentProvider,
              reconnectAttempts: status.reconnectAttempts,
            },
          },
        };
      } else {
        return {
          [key]: {
            status: 'down',
            message: `Event listener issues: listening=${status.isListening}, reconnects=${status.reconnectAttempts}`,
            details: {
              isListening: status.isListening,
              currentProvider: status.currentProvider,
              reconnectAttempts: status.reconnectAttempts,
            },
          },
        };
      }
    } catch (error) {
      return {
        [key]: {
          status: 'down',
          message: error.message || 'Event listener health check failed',
        },
      };
    }
  }
}