local extglob = require('canola.extglob')

describe('extglob', function()
  describe('expand', function()
    it('passes through plain text', function()
      assert.are.same({ 'hello' }, extglob.expand('hello'))
    end)

    it('passes through text with no braces', function()
      assert.are.same({ 'foo.txt' }, extglob.expand('foo.txt'))
    end)

    it('expands simple alternation', function()
      assert.are.same({ 'a', 'b', 'c' }, extglob.expand('{a,b,c}'))
    end)

    it('expands with prefix', function()
      assert.are.same({ 'foo.js', 'foo.ts' }, extglob.expand('foo.{js,ts}'))
    end)

    it('expands with suffix', function()
      assert.are.same({ 'a.txt', 'b.txt' }, extglob.expand('{a,b}.txt'))
    end)

    it('expands with prefix and suffix', function()
      assert.are.same({ 'test_a.lua', 'test_b.lua' }, extglob.expand('test_{a,b}.lua'))
    end)

    it('expands numeric range ascending', function()
      assert.are.same({ '1', '2', '3', '4', '5' }, extglob.expand('{1..5}'))
    end)

    it('expands numeric range descending', function()
      assert.are.same({ '5', '4', '3', '2', '1' }, extglob.expand('{5..1}'))
    end)

    it('expands range with step', function()
      assert.are.same({ '1', '3', '5', '7', '9' }, extglob.expand('{1..10..2}'))
    end)

    it('expands descending range with step', function()
      assert.are.same({ '10', '8', '6', '4', '2' }, extglob.expand('{10..1..2}'))
    end)

    it('expands range with negative numbers', function()
      assert.are.same({ '-2', '-1', '0', '1', '2' }, extglob.expand('{-2..2}'))
    end)

    it('expands range with prefix and suffix', function()
      assert.are.same({ 'file1.txt', 'file2.txt', 'file3.txt' }, extglob.expand('file{1..3}.txt'))
    end)

    it('expands nested braces', function()
      assert.are.same({ 'a', 'b', 'c' }, extglob.expand('{a,{b,c}}'))
    end)

    it('expands deeply nested braces', function()
      assert.are.same({ 'a', 'b', 'c', 'd' }, extglob.expand('{a,{b,{c,d}}}'))
    end)

    it('expands cartesian product of two groups', function()
      assert.are.same({ 'a_1', 'a_2', 'a_3', 'b_1', 'b_2', 'b_3' }, extglob.expand('{a,b}_{1..3}'))
    end)

    it('expands cartesian product of alternation and alternation', function()
      assert.are.same({ 'ax', 'ay', 'bx', 'by' }, extglob.expand('{a,b}{x,y}'))
    end)

    it('treats single item in braces as literal', function()
      assert.are.same({ '{foo}' }, extglob.expand('{foo}'))
    end)

    it('treats empty braces as literal', function()
      assert.are.same({ '{}' }, extglob.expand('{}'))
    end)

    it('handles alternation with nested braces in items', function()
      assert.are.same({ 'foo.test.js', 'foo.js' }, extglob.expand('foo.{test.js,js}'))
    end)

    it('handles multiple brace groups sequentially', function()
      assert.are.same({ 'a1', 'a2', 'b1', 'b2' }, extglob.expand('{a,b}{1,2}'))
    end)

    it('expands range with step of 3', function()
      assert.are.same({ '0', '3', '6', '9' }, extglob.expand('{0..9..3}'))
    end)

    it('treats unmatched opening brace as literal', function()
      assert.are.same({ '{foo' }, extglob.expand('{foo'))
    end)

    it('handles comma in nested braces correctly', function()
      assert.are.same({ 'a-x', 'a-y', 'b' }, extglob.expand('{{a-x,a-y},b}'))
    end)

    it('expands range with negative step', function()
      assert.are.same({ '10', '7', '4', '1' }, extglob.expand('{10..1..3}'))
    end)

    it('handles negative step as positive for descending', function()
      assert.are.same({ '10', '8', '6', '4', '2' }, extglob.expand('{10..1..-2}'))
    end)
  end)
end)
