// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import 'ds-test/test.sol';
import 'solmate/utils/FixedPointMathLib.sol';

contract TestHelpers is DSTest {
	using FixedPointMathLib for uint256;

	function assertCloseTo(
		uint256 a,
		uint256 b,
		uint256 d // 1 = 0.1%
	) internal {
		uint256 maxDelta = b.mulDivUp(d, 1000);
		uint256 delta = a > b ? a - b : b - a;

		if (delta > maxDelta) {
			emit log('Error: a ~= b not satisfied [uint]');
			emit log_named_uint('  Expected', b);
			emit log_named_uint('    Actual', a);
			emit log_named_uint(' Max Delta', maxDelta);
			emit log_named_uint('     Delta', delta);
			fail();
		}
	}
}
