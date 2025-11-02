require 'swagger_helper'

describe 'RPC API' do
  path '/rpc' do
    post 'JSON-RPC 2.0 endpoint' do
      tags 'RPC'
      consumes 'application/json'
      produces 'application/json'
      security [ Bearer: [] ]

      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          jsonrpc: { type: :string, example: '2.0' },
          method:  { type: :string, example: 'partidos.list' },
          params:  { type: :object },
          id:      { oneOf: [{ type: :integer }, { type: :string }] }
        },
        required: ['jsonrpc','method','id']
      }

      response '200', 'JSON-RPC result' do
        let(:payload) { { jsonrpc: '2.0', method: 'partidos.list', id: 1 } }
        run_test!
      end

      response '400', 'invalid request' do
        let(:payload) { { foo: 'bar' } }
        run_test!
      end
    end
  end
end