#!/usr/bin/env bash
# ================================================================================================
#
#   ___     _      _               ___ _                         ___         _    __     _ _      
# | _ \___| |_  _| |__ __ _ _ _  | _ (_)_ _  __ _ _ _  __ ___  | _ \___ _ _| |_ / _|___| (_)___  
# |  _/ _ | | || | '_ / _` | '_| | _ | | ' \/ _` | ' \/ _/ -_) |  _/ _ | '_|  _|  _/ _ | | / _ \ 
# |_| \___|_|\_, |_.__\__,_|_|   |___|_|_||_\__,_|_||_\__\___| |_| \___|_|  \__|_| \___|_|_\___/ 
#            |__/                                                                                 
#                            Script by @SocketByte (Adam Grzegorzewski)
#
# ================================================================================================
# !!! This script requires jq, curl, bc, grep, sed and openssl to be installed.
# !!! Only Binance SPOT accounts are currently supported.
# ================================================================================================
#
# Font Awesome 5 Icons used in the example:
#     
#
# Output format, this will be echoed to polybar.
# Available variables:
# - {CURRENCY}: Your selected FIAT currency.
# - {BALANCE}: The current portfolio balance adjusted for the selected currency.
# (You have to enable COINSTATS_USE to be able to use these variables)
# - {CS_USD_PRICE}: The current price of your selected currency in USD.
# - {CS_PNL_PERCENT}: The current profit/loss percentage of your portfolio.
# - {CS_PNL}: The current profit/loss of your portfolio adjusted for the selected currency.
# - {CS_PNL_ICON}: The current profit/loss icon.
# - {CS_PNL_DAILY_PERCENT}: The current profit/loss percentage of your portfolio in the last 24 hours.
# - {CS_PNL_DAILY}: The current profit/loss of your portfolio in the last 24 hours adjusted for the selected currency.
# - {CS_PNL_DAILY_ICON}: The current profit/loss icon in the last 24 hours.
FORMAT="\${BALANCE}"
# Example with CoinStats:
# FORMAT="\${BALANCE} {CS_PNL_DAILY_ICON} {CS_PNL_DAILY_PERCENT}%%{F-} (\${CS_PNL_DAILY})"

# An icon/label for {CS_PNL_ICON} or {CS_PNL_DAILY_ICON}.
ICON_UP="%{F#b8bb26}UP"
ICON_DOWN="%{F#fb4934}DOWN"

# Create an API key with at least a "Reading" permission.
# https://www.binance.com/my/settings/api-management
API_KEY=""
SECRET_KEY=""

# Please set your preferred currency here.
# Keep in mind that the currency converter API is not required for USD.
FIAT_CURRENCY="USD"

# You only need this if your FIAT_CURRENCY is not USD.
# https://www.currencyconverterapi.com/
CURRCONV_API_KEY=""

# !!! EXPERIMENTAL
# Use CoinStats scraper to get more data about your portfolio.
# This uses an UNOFFICIAL way to scrape data, so it's prone to breakage at ANY moment.
COINSTATS_USE=No # Set to Yes to enable.
COINSTATS_PORTFOLIO_URL="" 
# ================================================================================================
#
# ... The script begins here ...
#
TIMESTAMP=$(date +%s%N | cut -b1-13)
SIGNATURE=$(echo -n "timestamp=${TIMESTAMP}" | openssl dgst -sha256 -hmac $SECRET_KEY)
TRIMMED_SIGNATURE=$(echo $SIGNATURE | cut -d " " -f2)
SPOT_BALANCE_LIST=$(curl -s -H "X-MBX-APIKEY: ${API_KEY}" -X GET "https://api.binance.com/api/v3/account?timestamp=${TIMESTAMP}&signature=${TRIMMED_SIGNATURE}")

if [ "$FIAT_CURRENCY" != "USD" ]; then
    FIAT_CONV_RATE=$(curl -s "https://free.currconv.com/api/v7/convert?q=USD_${FIAT_CURRENCY}&compact=ultra&apiKey=${CURRCONV_API_KEY}" | jq -r ".USD_${FIAT_CURRENCY}")
fi

ASSETS=$(echo $SPOT_BALANCE_LIST | jq -r '.balances[] | select((.free|tonumber) > 0) | "\(.asset):\(.free)\n"')
for ASSET in $ASSETS; do
    ASSET_NAME=$(echo $ASSET | cut -d ":" -f1)
    ASSET_QUANTITY=$(echo $ASSET | cut -d ":" -f2)
    ASSET_USDT_PRICE=$(curl -s "https://api.binance.com/api/v3/ticker/price?symbol=${ASSET_NAME}USDT" | jq -r '.price')
    if [ "$FIAT_CURRENCY" != "USD" ]; then
        ASSET_VALUE=$(echo "$ASSET_USDT_PRICE * $ASSET_QUANTITY * $FIAT_CONV_RATE" | bc)
    else
        ASSET_VALUE=$(echo "$ASSET_USDT_PRICE * $ASSET_QUANTITY" | bc)
    fi

    TOTAL_VALUE=$(echo "scale=2; $TOTAL_VALUE + $ASSET_VALUE" | bc)
done

TOTAL_VALUE=$(echo "scale=2; $TOTAL_VALUE / 1" | bc)

if [ "$COINSTATS_USE" = "Yes" ]; then
    # This can change at ANY moment, use at your own risk.
    QUERY_PREFIX='.props.initialState.portfolio.shareablePortfolio.portfolio'
    QUERY_JSON=$(curl -s $COINSTATS_PORTFOLIO_URL | grep -oP '{"props"(.*)true}')

    CS_USD_PRICE=$(echo $QUERY_JSON | jq -r "${QUERY_PREFIX}.price.USD")
    CS_PNL_PERCENT=$(echo $QUERY_JSON | jq -r "${QUERY_PREFIX}.profitPercent.USD")
    CS_PNL=$(echo $QUERY_JSON | jq -r "${QUERY_PREFIX}.profit.USD")
    CS_PNL_DAILY_PERCENT=$(echo $QUERY_JSON | jq -r "${QUERY_PREFIX}.portfolio_percent_24.USD")
    CS_PNL_DAILY=$(echo $QUERY_JSON | jq -r "${QUERY_PREFIX}.portfolio_profit_24.USD")

    if [ "$FIAT_CURRENCY" != "USD" ]; then
        CS_PNL=$(echo "scale=2; $CS_PNL * $FIAT_CONV_RATE / 1" | bc)
        CS_PNL_DAILY=$(echo "scale=2; $CS_PNL_DAILY * $FIAT_CONV_RATE / 1" | bc)
    fi

    CS_USD_PRICE=$(echo "scale=2; $CS_USD_PRICE / 1" | bc)
    CS_PNL_PERCENT=$(echo "scale=2; $CS_PNL_PERCENT / 1" | bc)
    CS_PNL_DAILY_PERCENT=$(echo "scale=2; $CS_PNL_DAILY_PERCENT / 1" | bc)

    if (( $(echo "$CS_PNL_PERCENT > 0" | bc -l) )); then
        CS_PNL_ICON=$ICON_UP
    else
        CS_PNL_ICON=$ICON_DOWN
    fi

    if (( $(echo "$CS_PNL_DAILY_PERCENT > 0" | bc -l) )); then
        CS_PNL_DAILY_ICON=$ICON_UP
    else
        CS_PNL_DAILY_ICON=$ICON_DOWN
    fi
fi

echo $FORMAT \
    | sed "s/{CURRENCY}/$FIAT_CURRENCY/g" \
    | sed "s/{BALANCE}/$TOTAL_VALUE/g" \
    | sed "s/{CS_USD_PRICE}/$CS_USD_PRICE/g" \
    | sed "s/{CS_PNL_PERCENT}/$CS_PNL_PERCENT/g" \
    | sed "s/{CS_PNL}/$CS_PNL/g" \
    | sed "s/{CS_PNL_DAILY_PERCENT}/$CS_PNL_DAILY_PERCENT/g" \
    | sed "s/{CS_PNL_DAILY}/$CS_PNL_DAILY/g" \
    | sed "s/{CS_PNL_ICON}/$CS_PNL_ICON/g" \
    | sed "s/{CS_PNL_DAILY_ICON}/$CS_PNL_DAILY_ICON/g"