#!/usr/bin/env python3
"""
MyCodeAssistant Documentation Crawler
Crawls ref.ai/refs.dev documentation and indexes it in Cloudflare Vectorize
"""

import os
import sys
import json
import logging
import asyncio
from typing import List, Dict, Any
from datetime import datetime
import hashlib

# Required packages
try:
    import requests
    from langchain_community.document_loaders import WebBaseLoader
    from langchain.text_splitter import RecursiveCharacterTextSplitter
    from langchain.schema import Document
except ImportError as e:
    print(f"Error: Missing required package - {e}")
    print("Install with: pip install requests langchain langchain-community")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
CLOUDFLARE_ACCOUNT_ID = os.getenv("CLOUDFLARE_ACCOUNT_ID", "091c9e59ca0fc3bea9f9d432fa12a3b1")
CLOUDFLARE_API_TOKEN = os.getenv("CLOUDFLARE_API_TOKEN", "")
VECTORIZE_INDEX = "mca-embeddings"
WORKERS_URL = os.getenv("WORKERS_URL", "https://agents-starter.wmeldman33.workers.dev")

# Documentation sources
DOCUMENTATION_SOURCES = {
    "swift": [
        "https://developer.apple.com/documentation/swift",
        "https://docs.swift.org/swift-book/",
        "https://www.swift.org/documentation/",
    ],
    "python": [
        "https://docs.python.org/3/",
        "https://docs.python.org/3/tutorial/",
        "https://docs.python.org/3/library/",
    ],
    "cloudflare": [
        "https://developers.cloudflare.com/workers/",
        "https://developers.cloudflare.com/vectorize/",
        "https://developers.cloudflare.com/d1/",
        "https://developers.cloudflare.com/r2/",
    ],
    "langchain": [
        "https://python.langchain.com/docs/get_started/introduction",
        "https://python.langchain.com/docs/modules/",
    ]
}


class CloudflareVectorIndexer:
    """Handles indexing documents to Cloudflare Vectorize"""
    
    def __init__(self, account_id: str, api_token: str, index_name: str):
        self.account_id = account_id
        self.api_token = api_token
        self.index_name = index_name
        self.workers_url = WORKERS_URL
        
    def generate_embedding_id(self, text: str, metadata: Dict) -> str:
        """Generate a unique ID for an embedding"""
        content = f"{text}{json.dumps(metadata, sort_keys=True)}"
        return hashlib.sha256(content.encode()).hexdigest()[:16]
    
    async def add_documents(self, documents: List[Document]) -> Dict[str, Any]:
        """Add documents to Vectorize via Workers endpoint"""
        results = {
            "success": 0,
            "failed": 0,
            "errors": []
        }
        
        # Batch documents for efficient processing
        batch_size = 10
        for i in range(0, len(documents), batch_size):
            batch = documents[i:i + batch_size]
            
            # Prepare batch payload
            batch_documents = []
            for doc in batch:
                doc_id = self.generate_embedding_id(doc.page_content, doc.metadata)
                batch_documents.append({
                    "id": doc_id,
                    "text": doc.page_content[:4096],  # Limit text length
                    "metadata": {
                        **doc.metadata,
                        "indexed_at": datetime.utcnow().isoformat(),
                        "source": "refs_dev_crawler"
                    }
                })
            
            # Send to Workers endpoint
            try:
                response = requests.post(
                    f"{self.workers_url}/embeddings/batch",
                    json={
                        "documents": batch_documents,
                        "namespace": "documentation",
                        "source": "refs_dev_crawler"
                    },
                    headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {self.api_token}" if self.api_token else None
                    },
                    timeout=30
                )
                
                if response.status_code == 200:
                    result = response.json()
                    if result.get("success"):
                        results["success"] += len(batch)
                        logger.info(f"Successfully indexed batch of {len(batch)} documents")
                    else:
                        results["failed"] += len(batch)
                        results["errors"].append(result.get("error", "Unknown error"))
                else:
                    results["failed"] += len(batch)
                    error_msg = f"HTTP {response.status_code}: {response.text}"
                    results["errors"].append(error_msg)
                    logger.error(f"Failed to index batch: {error_msg}")
                    
            except Exception as e:
                results["failed"] += len(batch)
                results["errors"].append(str(e))
                logger.error(f"Exception indexing batch: {e}")
        
        return results
    
    def search(self, query: str, top_k: int = 5) -> List[Dict]:
        """Search for similar documents"""
        try:
            response = requests.post(
                f"{self.workers_url}/embeddings/search",
                json={
                    "query": query,
                    "topK": top_k,
                    "namespace": "documentation"
                },
                headers={"Content-Type": "application/json"},
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                return data.get("results", [])
            else:
                logger.error(f"Search failed: HTTP {response.status_code}")
                return []
                
        except Exception as e:
            logger.error(f"Search exception: {e}")
            return []


class RefsDevCrawler:
    """Crawls and processes documentation from various sources"""
    
    def __init__(self, indexer: CloudflareVectorIndexer):
        self.indexer = indexer
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=1000,
            chunk_overlap=200,
            length_function=len,
            separators=["\n\n", "\n", " ", ""]
        )
    
    def load_documentation(self, url: str, language: str) -> List[Document]:
        """Load and split documentation from a URL"""
        documents = []
        
        try:
            logger.info(f"Loading documentation from: {url}")
            
            # Use WebBaseLoader for web pages
            loader = WebBaseLoader(url)
            raw_docs = loader.load()
            
            # Split documents into chunks
            for doc in raw_docs:
                # Add metadata
                doc.metadata.update({
                    "language": language,
                    "source_url": url,
                    "doc_type": "reference"
                })
                
                # Split into chunks
                chunks = self.text_splitter.split_documents([doc])
                documents.extend(chunks)
            
            logger.info(f"Loaded {len(documents)} chunks from {url}")
            
        except Exception as e:
            logger.error(f"Failed to load {url}: {e}")
        
        return documents
    
    async def crawl_all_sources(self) -> Dict[str, Any]:
        """Crawl all documentation sources"""
        all_documents = []
        stats = {
            "languages": {},
            "total_documents": 0,
            "total_chunks": 0
        }
        
        for language, urls in DOCUMENTATION_SOURCES.items():
            language_docs = []
            
            for url in urls:
                docs = self.load_documentation(url, language)
                language_docs.extend(docs)
            
            stats["languages"][language] = len(language_docs)
            all_documents.extend(language_docs)
            
            logger.info(f"Collected {len(language_docs)} chunks for {language}")
        
        stats["total_documents"] = len(DOCUMENTATION_SOURCES)
        stats["total_chunks"] = len(all_documents)
        
        # Index all documents
        if all_documents:
            logger.info(f"Indexing {len(all_documents)} total chunks...")
            index_results = await self.indexer.add_documents(all_documents)
            stats["indexing"] = index_results
        else:
            logger.warning("No documents to index")
            stats["indexing"] = {"success": 0, "failed": 0}
        
        return stats


class RefAIClient:
    """Alternative client for ref.ai if available"""
    
    def __init__(self):
        self.base_url = "https://api.ref.ai/v1"
        
    def search_references(self, query: str, languages: List[str]) -> List[Dict]:
        """Search programming references"""
        # This would connect to ref.ai API if available
        # For now, returns mock data
        return [
            {
                "title": f"Swift: {query}",
                "url": "https://developer.apple.com/documentation/",
                "snippet": "Swift documentation reference"
            }
        ]


async def main():
    """Main entry point"""
    print("🚀 MyCodeAssistant Documentation Crawler")
    print("=" * 50)
    
    # Check for API token
    if not CLOUDFLARE_API_TOKEN:
        logger.warning("No CLOUDFLARE_API_TOKEN set, using public endpoints only")
    
    # Initialize components
    indexer = CloudflareVectorIndexer(
        account_id=CLOUDFLARE_ACCOUNT_ID,
        api_token=CLOUDFLARE_API_TOKEN,
        index_name=VECTORIZE_INDEX
    )
    
    crawler = RefsDevCrawler(indexer)
    
    # Test Workers connectivity
    print("\n🔍 Testing Workers connectivity...")
    try:
        response = requests.get(f"{WORKERS_URL}/health", timeout=5)
        if response.status_code == 200:
            print("✅ Workers endpoint is accessible")
        else:
            print(f"⚠️  Workers returned status {response.status_code}")
    except Exception as e:
        print(f"❌ Cannot reach Workers: {e}")
        print("Continuing anyway...")
    
    # Crawl documentation
    print("\n📚 Starting documentation crawl...")
    stats = await crawler.crawl_all_sources()
    
    # Display results
    print("\n" + "=" * 50)
    print("📊 Crawl Statistics")
    print("=" * 50)
    
    for language, count in stats["languages"].items():
        print(f"  {language}: {count} chunks")
    
    print(f"\nTotal chunks: {stats['total_chunks']}")
    
    if "indexing" in stats:
        print(f"\nIndexing results:")
        print(f"  ✅ Success: {stats['indexing']['success']}")
        print(f"  ❌ Failed: {stats['indexing']['failed']}")
        
        if stats['indexing']['errors']:
            print(f"\n⚠️  Errors encountered:")
            for error in stats['indexing']['errors'][:5]:  # Show first 5 errors
                print(f"    - {error}")
    
    # Test search functionality
    print("\n🔍 Testing search functionality...")
    test_queries = [
        "Swift async await",
        "Python decorators",
        "Cloudflare Workers KV"
    ]
    
    for query in test_queries:
        results = indexer.search(query, top_k=3)
        print(f"\nQuery: '{query}'")
        if results:
            print(f"  Found {len(results)} results")
            for i, result in enumerate(results[:2], 1):
                print(f"    {i}. Score: {result.get('score', 'N/A')}")
        else:
            print("  No results found")
    
    print("\n✅ Documentation crawl complete!")
    
    # Save stats to file for monitoring
    stats_file = "crawler_stats.json"
    with open(stats_file, "w") as f:
        json.dump({
            "timestamp": datetime.utcnow().isoformat(),
            "stats": stats
        }, f, indent=2)
    print(f"\n📁 Stats saved to {stats_file}")
    
    return stats


def schedule_daily():
    """Entry point for Cloudflare Workers scheduled job"""
    # This would be called by a Cloudflare Worker on a schedule
    asyncio.run(main())


if __name__ == "__main__":
    # Run the crawler
    asyncio.run(main())