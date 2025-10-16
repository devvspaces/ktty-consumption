import { Controller, Get } from '@nestjs/common';
import {
  HealthCheckService,
  HealthCheck,
  MemoryHealthIndicator,
  DiskHealthIndicator,
} from '@nestjs/terminus';
import { ContractService } from '../blockchain/services/contract.service';
import { DatabaseService } from '../../database/database.service';

@Controller('health')
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private memory: MemoryHealthIndicator,
    private disk: DiskHealthIndicator,
    private contractService: ContractService,
    private databaseService: DatabaseService,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      // Memory check - alert if memory usage is over 300MB
      () => this.memory.checkHeap('memory_heap', 300 * 1024 * 1024),
      
      // Disk check - alert if less than 1GB free space
      () => this.disk.checkStorage('storage', { 
        path: '/', 
        thresholdPercent: 0.9 
      }),

      // Database health check
      async () => {
        const isHealthy = await this.databaseService.healthCheck();
        return {
          database: {
            status: isHealthy ? 'up' : 'down',
          },
        };
      },

      // Contract/Provider health check
      async () => {
        const isHealthy = await this.contractService.healthCheck();
        return {
          contract: {
            status: isHealthy ? 'up' : 'down',
          },
        };
      },
    ]);
  }

  /**
   * Readiness check - determines if the application is ready to accept traffic
   */
  @Get('ready')
  @HealthCheck()
  ready() {
    return this.health.check([
      // Check if database is accessible
      async () => {
        const isHealthy = await this.databaseService.healthCheck();
        if (!isHealthy) {
          throw new Error('Database not ready');
        }
        return { database: { status: 'up' } };
      },

      // Check if contract is accessible
      async () => {
        const isHealthy = await this.contractService.healthCheck();
        if (!isHealthy) {
          throw new Error('Contract provider not ready');
        }
        return { contract: { status: 'up' } };
      },
    ]);
  }

  /**
   * Liveness check - determines if the application is still running
   */
  @Get('live')
  @HealthCheck()
  live() {
    return this.health.check([
      // Basic memory check
      () => this.memory.checkHeap('memory_heap', 500 * 1024 * 1024),
    ]);
  }
}