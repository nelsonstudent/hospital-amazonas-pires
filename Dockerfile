# ---- Build stage (opcional para apps estáticas, mas boa prática) ----
FROM nginx:1.27-alpine AS base

# Remove a config padrão do Nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copia nossa config customizada
COPY nginx.conf /etc/nginx/conf.d/app.conf

# Copia o HTML para o diretório público do Nginx
COPY index.html /usr/share/nginx/html/index.html

# Expõe a porta 8080 (não-root, boa prática para Kubernetes)
EXPOSE 8080

# Health check embutido na imagem
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

# Nginx já tem seu próprio entrypoint — apenas garantimos que rode em foreground
CMD ["nginx", "-g", "daemon off;"]
