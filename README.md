# Flujo de uso 

Flujo típico en tu app:

RpcController recibe llamada JSON-RPC.
Pasa token y parámetros a MCPService.
MCPService registra la spec (si no se ha registrado) y envía input al modelo vía SDK.
El modelo decide y (si usa la herramienta) el SDK ejecuta la llamada a tu API Gateway según la spec.
Si el SDK no soporta esa integración, MCPService hace la llamada HTTP directamente (fallback).