import test from'node:test';import assert from'node:assert/strict';import{edgeSpeed}from'../src/utils/gantt-drag-scroll.mjs';
test('center and outside viewport never initiate scrolling',()=>{for(const p of[-1,57,300,543,601])assert.equal(edgeSpeed(p,0,600),0);});
test('edges accelerate gradually with bounded symmetric physical directions',()=>{assert.equal(edgeSpeed(0,0,600),-720);assert.equal(edgeSpeed(600,0,600),720);assert.equal(edgeSpeed(28,0,600),-360);assert.equal(edgeSpeed(572,0,600),360);assert.equal(edgeSpeed(3,5,5),0);});
