import { SongItem } from '../models/music';
import fs from '@ohos.file.fs';

const AUDIO_EXTENSIONS: string[] = ['.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac', '.amr', '.webm'];

interface FileInfo {
  path: string;
  name: string;
  lastModified: number;
  size: number;
}

export async function scanLocalMusic(context: Context): Promise<SongItem[]> {
  const songList: SongItem[] = [];

  const cacheDir: string = context.cacheDir;
  const filesDir: string = context.filesDir;

  const musicDirs: string[] = [
    filesDir,
    cacheDir
  ];

  for (const dir of musicDirs) {
    if (!dir) continue;
    try {
      const files: FileInfo[] = await scanDirectory(dir);
      for (const file of files) {
        const ext: string = getFileExtension(file.name).toLowerCase();
        if (AUDIO_EXTENSIONS.includes(ext)) {
          const song = new SongItem();
          song.id = generateId(file.path);
          song.title = removeExtension(file.name);
          song.singer = '未知艺术家';
          song.src = file.path;
          song.index = songList.length;
          songList.push(song);
        }
      }
    } catch (e) {
      console.warn(`Cannot scan directory: ${dir}`);
    }
  }

  return songList;
}

async function scanDirectory(dirPath: string): Promise<FileInfo[]> {
  const results: FileInfo[] = [];

  try {
    const fileNames: string[] = fs.listFileSync(dirPath);
    for (const name of fileNames) {
      const fullPath: string = `${dirPath}/${name}`;
      try {
        const stat: fs.Stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
          const subResults: FileInfo[] = await scanDirectory(fullPath);
          results.push(...subResults);
        } else if (stat.isFile()) {
          results.push({
            path: fullPath,
            name: name,
            lastModified: stat.mtime,
            size: stat.size
          });
        }
      } catch (e) {
        // Skip files we can't access
      }
    }
  } catch (e) {
    // Directory doesn't exist or no permission
  }

  return results;
}

function getFileExtension(filename: string): string {
  const lastDot: number = filename.lastIndexOf('.');
  if (lastDot === -1) return '';
  return filename.substring(lastDot);
}

function removeExtension(filename: string): string {
  const lastDot: number = filename.lastIndexOf('.');
  if (lastDot === -1) return filename;
  return filename.substring(0, lastDot);
}

function generateId(path: string): number {
  let hash: number = 0;
  for (let i = 0; i < path.length; i++) {
    const char: number = path.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return Math.abs(hash);
}
