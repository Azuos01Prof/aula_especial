import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calcularDesconto } from '../src/precos.js';

test('aplica 10% de desconto', () => {
  assert.equal(calcularDesconto(200, 10), 180);
});

test('desconto zero mantém o preço', () => {
  assert.equal(calcularDesconto(50, 0), 50);
});

test('recusa preço negativo', () => {
  assert.throws(() => calcularDesconto(-5, 10));
});