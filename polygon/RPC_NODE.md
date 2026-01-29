I want to deploy a full node of Poylgon chain on this system. Use /mnt/viper2 as the data directory. Use plan mode and read
  the polygon docs throughly to find all the options you need to do to make it fast. You also need to find and install a
  snapshot since full-sync is out of window due to it being too slow. The main use case is to query blocks, transacitons
  and logs of the historical blocks. It should provide standard RPC interface that I can use with any web3 compatible
  program on the internet. Optimize it for query speed and less storage. Note that it should contian only main chain (not
  testnets) from genesis block until now. I don't plan to use it as a validator or use websockets so strip all the
  unneeded features, the only important thing is querying blocks, transactions and logs. 
