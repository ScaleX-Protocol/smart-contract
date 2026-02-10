#!/usr/bin/env python3
"""
Script to achieve target supply APYs for all lending pools
Based on targets defined in LENDING_APY_GOALS.md
"""

import subprocess
import json
import os

# Configuration
LENDING_MANAGER = "0xbe2e1Fe2bdf3c4AC29DEc7d09d0E26F06f29585c"
RPC_URL = "https://sepolia.base.org"

# Load deployments
with open('deployments/84532.json', 'r') as f:
    deployments = json.load(f)

SCALEX_ROUTER = deployments['ScaleXRouter']
PRIVATE_KEY = os.environ.get('PRIVATE_KEY')

# Target utilizations (in percentage)
targets = {
    'WBTC': {'util': 20.91, 'decimals': 8, 'status': 'achieved'},
    'WETH': {'util': 30.19, 'decimals': 18, 'status': 'pending'},
    'IDRX': {'util': 59.14, 'decimals': 6, 'status': 'pending'},
    'GOLD': {'util': 12.10, 'decimals': 6, 'status': 'pending'},
    'SILVER': {'util': 54.18, 'decimals': 6, 'status': 'pending'},
    'GOOGL': {'util': 25.54, 'decimals': 6, 'status': 'pending'},
    'NVDA': {'util': 30.23, 'decimals': 6, 'status': 'pending'},
    'AAPL': {'util': 13.77, 'decimals': 6, 'status': 'pending'},
    'MNT': {'util': 25.09, 'decimals': 6, 'status': 'pending'}
}

def get_pool_state(token_address):
    """Get current pool liquidity and borrowed amounts"""
    total_liq = subprocess.check_output([
        'cast', 'call', LENDING_MANAGER,
        f'totalLiquidity(address)(uint256)', token_address,
        '--rpc-url', RPC_URL
    ]).decode().strip().split()[0]

    total_borr = subprocess.check_output([
        'cast', 'call', LENDING_MANAGER,
        f'totalBorrowed(address)(uint256)', token_address,
        '--rpc-url', RPC_URL
    ]).decode().strip().split()[0]

    return int(total_liq), int(total_borr)

def borrow_asset(token_address, amount):
    """Execute a borrow transaction"""
    try:
        result = subprocess.run([
            'cast', 'send', SCALEX_ROUTER,
            f'borrow(address,uint256)', token_address, str(amount),
            '--private-key', PRIVATE_KEY,
            '--rpc-url', RPC_URL,
            '--gas-limit', '2000000'
        ], capture_output=True, text=True, timeout=60)

        if 'transactionHash' in result.stdout:
            tx_hash = [line for line in result.stdout.split('\n') if 'transactionHash' in line][0]
            return True, tx_hash
        else:
            return False, result.stderr
    except Exception as e:
        return False, str(e)

def main():
    print("=" * 70)
    print("ACHIEVING TARGET SUPPLY APYs FOR ALL LENDING POOLS")
    print("=" * 70)
    print()
    print(f"LendingManager: {LENDING_MANAGER}")
    print(f"Router: {SCALEX_ROUTER}")
    print()

    results = []

    for asset, config in targets.items():
        if config['status'] == 'achieved':
            print(f"✅ {asset}: Already achieved")
            continue

        token_address = deployments.get(asset)
        if not token_address:
            print(f"⚠️  {asset}: Not found in deployments")
            continue

        print(f"\n{asset} (Target: {config['util']:.2f}% utilization)")
        print("-" * 70)

        try:
            # Get current state
            total_liq, total_borr = get_pool_state(token_address)
            decimals = config['decimals']

            total_liq_float = total_liq / (10 ** decimals)
            total_borr_float = total_borr / (10 ** decimals)
            current_util = (total_borr_float / total_liq_float * 100) if total_liq_float > 0 else 0

            print(f"  Current: {total_liq_float:,.2f} liquidity, {total_borr_float:,.2f} borrowed")
            print(f"  Utilization: {current_util:.2f}% → Target: {config['util']:.2f}%")

            # Calculate borrow needed
            target_borr = total_liq_float * (config['util'] / 100)
            additional_borrow = max(0, target_borr - total_borr_float)
            additional_borrow_raw = int(additional_borrow * (10 ** decimals))

            if additional_borrow_raw > 0:
                print(f"  Need to borrow: {additional_borrow:,.2f} {asset}")
                print(f"  Executing borrow...")

                success, result = borrow_asset(token_address, additional_borrow_raw)

                if success:
                    print(f"  ✅ Borrow successful")
                    print(f"  {result}")
                    results.append((asset, 'success', additional_borrow))
                else:
                    print(f"  ❌ Borrow failed: {result}")
                    results.append((asset, 'failed', additional_borrow))
            else:
                print(f"  ✅ Already at target utilization")
                results.append((asset, 'no_action', 0))

        except Exception as e:
            print(f"  ❌ Error: {e}")
            results.append((asset, 'error', 0))

    print()
    print("=" * 70)
    print("SUMMARY")
    print("=" * 70)
    for asset, status, amount in results:
        if status == 'success':
            print(f"✅ {asset}: Borrowed {amount:,.2f}")
        elif status == 'failed':
            print(f"❌ {asset}: Failed to borrow {amount:,.2f}")
        elif status == 'no_action':
            print(f"✓  {asset}: Already at target")
        else:
            print(f"⚠️  {asset}: Error occurred")

    print()
    print("Verify results:")
    print("  Dashboard: http://localhost:42070/api/lending/dashboard/0xc8E6F712902DCA8f50B10Dd7Eb3c89E5a2Ed9a2a")

if __name__ == '__main__':
    main()
