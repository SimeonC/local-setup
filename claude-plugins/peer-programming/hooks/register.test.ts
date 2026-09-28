import { expect, test } from 'claude-code/testing'
import { isTestFile } from './register'

test('test file policy accepts conventional files across supported languages', () => {
  for (const path of [
    'src/cache.test.ts',
    'src/__tests__/cache.ts',
    'spec/cache_spec.rb',
    'lib/cache_test.go',
    'test/cache_test.exs',
    'Tests/StoreTests/StoreTests.swift',
    'tests/notebook_test.ipynb',
  ]) {
    expect(isTestFile(path)).toBe(true)
  }
})

test('test file policy does not allow implementation paths', () => {
  for (const path of [
    'src/cache.ts',
    'app/models/cache.rb',
    'pkg/cache.go',
    'lib/cache.ex',
    'Sources/Store/Store.swift',
    'notebooks/prototype.ipynb',
  ]) {
    expect(isTestFile(path)).toBe(false)
  }
})
