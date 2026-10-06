FROM node:20-alpine

# sharp renders the watermark and share-card text from SVG, which needs real
# fonts + fontconfig present in the image (Alpine ships none by default).
RUN apk add --no-cache fontconfig font-dejavu && fc-cache -f

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev
COPY src ./src
RUN mkdir -p /app/uploads
EXPOSE 3000
CMD ["node", "src/server.js"]
