import { Injectable, OnModuleInit } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { createBullBoard } from '@bull-board/api';
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter';
import { ExpressAdapter } from '@bull-board/express';

@Injectable()
export class BullBoardService implements OnModuleInit {
  private serverAdapter: ExpressAdapter;

  constructor(
    @InjectQueue('metadata') private metadataQueue: Queue,
  ) {
    this.serverAdapter = new ExpressAdapter();
    this.serverAdapter.setBasePath('/admin/queues');
  }

  onModuleInit() {
    createBullBoard({
      queues: [
        new BullMQAdapter(this.metadataQueue),
      ],
      serverAdapter: this.serverAdapter,
    });
  }

  getRouter() {
    return this.serverAdapter.getRouter();
  }
}