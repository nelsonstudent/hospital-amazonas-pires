FROM nginx:1.27-alpine

# Atualiza todos os pacotes do Alpine para versões corrigidas
RUN apk update && apk upgrade --no-cache

# Remove configuração padrão
RUN rm -f /etc/nginx/conf.d/default.conf

# Configuração customizada
COPY nginx.conf /etc/nginx/conf.d/app.conf

# Aplicação
COPY index.html /usr/share/nginx/html/index.html

# Porta da aplicação
EXPOSE 8080

# Healthcheck
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

# Executa Nginx em foreground
CMD ["nginx", "-g", "daemon off;"]
