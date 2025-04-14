import { ApolloClient } from 'apollo-client'
import { InMemoryCache } from 'apollo-cache-inmemory'
import { HttpLink } from 'apollo-link-http'

export const client = new ApolloClient({
  link: new HttpLink({
    // uri: 'http://192.168.5.20:8000/subgraphs/name/tuvs85/Cherrytesswap',
    uri: 'https://info.cherryswap.net/subgraphs/name/cherryswap/subgraph',
  }),
  cache: new InMemoryCache(),
  shouldBatch: true,
})

export const healthClient = new ApolloClient({
  link: new HttpLink({
    // uri: 'http://192.168.5.20:8030/graphql',
    uri: 'https://info.cherryswap.net/graphql',
  }),
  cache: new InMemoryCache(),
  shouldBatch: true,
})

export const blockClient = new ApolloClient({
  link: new HttpLink({
    // uri: 'http://192.168.5.20:8000/subgraphs/name/tuvs85/cherrytblock',
    uri: 'https://info.cherryswap.net/subgraphs/name/tuvs85/cherrytblock'
  }),
  cache: new InMemoryCache(),
})
